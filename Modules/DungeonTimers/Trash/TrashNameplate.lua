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
local math_max = math.max
local math_floor = math.floor
local math_abs = math.abs
local table_sort = table.sort
local ipairs = ipairs
local pairs = pairs

local MARKER_REFRESH = 1.0   -- count-text repaint cadence (swipe is native)
local ICON_CROP = 0.08       -- upstream reference's 0.08–0.92 plate-icon crop
                             -- (deliberate port fidelity; KE's central alerts
                             -- use KE:ApplyIconZoom's 0.075 — visually equal)
local PREDICTION_GRACE = 10.0 -- ready-linger: drop a prediction this many
                              -- seconds past its nextStart if no re-cast
                              -- refreshed it (both references keep a ready
                              -- bar for 10 seconds by default), so the
                              -- green "due now" cue holds, then the ticker idles

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
    -- secret) width and throws inside SetCooldown (Backdrop.lua). Plain
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
    -- Strata is applied from config in UpdateNameplateMarker (db.Nameplate.Strata,
    -- default MEDIUM) so a GUI change repaints live; nothing to hardcode here.
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
    local side = cfg.AnchorSide or "LEFT"
    local ox, oy = cfg.OffsetX or 0, cfg.OffsetY or 0

    -- Anchor the marker just off the requested EDGE of the plate; the icon row
    -- then grows AWAY from the plate, so it can never overlap the bar. OffsetX/Y
    -- nudge from there.
    --   LEFT  → marker's right edge at the plate's left edge, icons grow left.
    --   RIGHT → mirror, icons grow right.
    --   TOP   → marker centred above the plate's top edge, icons in a centred row.
    marker:ClearAllPoints()
    if side == "TOP" then
        marker:SetPoint("BOTTOM", anchor, "TOP", ox, gap + oy)
    elseif side == "LEFT" then
        marker:SetPoint("RIGHT", anchor, "LEFT", -gap + ox, oy)
    else
        marker:SetPoint("LEFT", anchor, "RIGHT", gap + ox, oy)
    end
    marker:Show()

    -- Full row width, for centring the TOP layout on the plate (soonest-first).
    local rowSpan = #order * size + (#order - 1) * gap

    for i, entry in ipairs(order) do
        local icon = marker.icons[i]
        if not icon then icon = buildIcon(marker); marker.icons[i] = icon end
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        -- First (soonest) icon nearest the plate; subsequent grow outward. TOP
        -- lays the same order out left-to-right, centred over the plate.
        local step = (i - 1) * (size + gap)
        if side == "TOP" then
            icon:SetPoint("BOTTOM", marker, "BOTTOM", -rowSpan / 2 + step + size / 2, 0)
        elseif side == "LEFT" then
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
    -- Direct call, no method-existence guard: Trash.xml loads DungeonTrash.lua
    -- (which defines it) before this file, and a correctness gate must fail
    -- LOUD on a rename, not silently fall open.
    if self:IsBossOutputSuppressed() then
        self:HideNameplateMarker(unit)
        return
    end
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

    -- Frame strata (db.Nameplate.Strata, default MEDIUM). Guarded so the ~1s
    -- ticker and every RefreshMarkers pass only call SetFrameStrata on a change.
    local strata = cfg.Strata or "MEDIUM"
    if marker._strata ~= strata then
        marker:SetFrameStrata(strata)
        marker._strata = strata
    end

    local now = GetTime()

    -- Build the icon order by soonest cast, pruning any prediction that has sat
    -- past its nextStart with no re-cast to refresh it (deleting the current
    -- key mid-pairs is defined in 5.1). Without this an icon sticks on "ready"
    -- forever and the idle ticker can never go quiet. The per-spell gates are
    -- re-checked here too (mirrors SetNameplatePrediction's arm-time set): a
    -- mid-dungeon disable / role change / show-on-plate toggle must drop the
    -- STORED prediction, not just block the next arm — the reference rebuilds
    -- through its gates on every config revision.
    local order = {}
    local npcID = rt.matchedNPCID
    for spellID, pred in pairs(rt.predictions) do
        local drop = now - (pred.nextStart or 0) > PREDICTION_GRACE
        if not drop and npcID then
            drop = (self.IsTrashSpellDisabled and self:IsTrashSpellDisabled(npcID, spellID))
                or (self.PlayerSeesTrashSpell
                    and not self:PlayerSeesTrashSpell(self.currentMapID, npcID, spellID))
                or (self.GetSpellShowNameplate
                    and not self:GetSpellShowNameplate(self.currentMapID, npcID, spellID))
        end
        if drop then
            rt.predictions[spellID] = nil
        else
            order[#order + 1] = { spellID = spellID, pred = pred }
        end
    end
    if not next(rt.predictions) then
        self:HideNameplateMarker(unit)
        return
    end
    table_sort(order, function(a, b)
        local an, bn = a.pred.nextStart or 0, b.pred.nextStart or 0
        -- spellID tie-break (reference parity): two spells seeded from the
        -- same engage with equal `first` must not swap slots between repaints.
        if an == bn then return a.spellID < b.spellID end
        return an < bn
    end)

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

-- Record/refresh a predicted cast for a unit and repaint its marker. npcID is
-- supplied by the emitter (EmitCastResolution): the deferred one-phase fallback
-- resolves against its ARM-time identity, which must key the per-ability gates
-- below even if Layer1 re-resolved the plate meanwhile.
function DTrash:SetNameplatePrediction(rt, npcID, spellID, startTime, nextStart)
    if not rt or not spellID then return end
    -- Arm-time blackout gate (mirrors ScheduleAlert): a prediction recorded
    -- during a blocklisted encounter carries exactly the mislabeled identity
    -- the blackout silences, and stored state would revive on the ticker the
    -- moment ENCOUNTER_END clears the flag. Predictions recorded BEFORE the
    -- encounter (trusted identity) stay stored and legitimately resume after.
    if self:IsBossOutputSuppressed() then return end
    npcID = npcID or rt.matchedNPCID
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
    -- startTime is the REGISTRATION moment (callers pass their `now`), never
    -- the schedule origin — the references stamp the swipe origin to now at
    -- register/reset, so a late-resolved or rolled anchor draws a fresh full
    -- swipe instead of a pre-drained (or future-dated, invisible) one.
    -- Continuity exception, also the reference's: a re-registration whose
    -- nextStart moved ≤0.75s keeps the old origin so a mere refresh of an
    -- unchanged schedule doesn't visibly restart the arc.
    local prev = rt.predictions[spellID]
    if prev and prev.startTime and prev.nextStart and nextStart
        and math_abs(nextStart - prev.nextStart) <= 0.75 then
        startTime = prev.startTime
    end
    rt.predictions[spellID] = { iconID = iconID, startTime = startTime, nextStart = nextStart }
    self:UpdateNameplateMarker(rt.unit)
    self:EnsureMarkerTicker()
end

-- ── Throttled refresh ───────────────────────────────────────────────────────

function DTrash:EnsureMarkerTicker()
    if self._markerTicker then return end
    self._markerTicker = C_Timer.NewTicker(MARKER_REFRESH, function()
        local anyLeft = false
        -- Drive from the RUNTIMES holding predictions, not the marker registry:
        -- a prediction whose first UpdateNameplateMarker early-returned (plate
        -- momentarily nil from C_NamePlate, or an encounter blackout) has no
        -- _markers entry yet — a markers-only loop would never visit it, cancel
        -- the ticker on anyLeft=false, and leave that icon invisible until the
        -- mob's next cast resolution. UpdateNameplateMarker creates the marker
        -- as soon as the plate is resolvable again.
        for unit, rt in pairs(self.tracked) do
            if rt.predictions and next(rt.predictions) then
                anyLeft = true
                self:UpdateNameplateMarker(unit)  -- repaints counts + re-anchors
            end
        end
        -- Sweep markers whose runtime/predictions are gone (plate removal
        -- already hides, but a prediction table can empty out via grace-prune).
        for unit, marker in pairs(self._markers) do
            local rt = self.tracked[unit]
            if not (rt and rt.predictions and next(rt.predictions)) and marker:IsShown() then
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

-- The sample renders at TRUE size (1:1) so the icons match the player's real
-- IconSize setting exactly — the scale only ever shrinks BELOW this to keep an
-- oversized plate+icon composite from overflowing the card, never enlarges
-- (enlarging inflated the icons and misrepresented their real size).
local PREVIEW_MAX_SCALE = 1.0

-- Pull the player's REAL configured bar dimensions from the active nameplate
-- addon's saved profile, so the stand-in matches what they actually see in a
-- dungeon rather than just the addon's ship default. Every read here walks
-- another addon's SavedVariables layout — which drifts between versions — so
-- the whole thing is pcall-wrapped and every value range-checked; on any miss
-- the caller falls back to the representative PLATE_FOOTPRINTS entry. Only
-- Plater and EUI store their bar geometry in a stable, readable form (Blizzard
-- is CVar-driven, Platynator's default design isn't written to SV); the rest
-- keep their footprint default. Returns healthW, healthH, castW, castH — any of
-- which may be nil.
local function saneW(v) v = tonumber(v); if v and v >= 40 and v <= 400 then return v end end
local function saneH(v) v = tonumber(v); if v and v >= 4 and v <= 80 then return v end end

local function readAddonPlateSize(detected)
    local hw, hh, cw, ch
    local ok = pcall(function()
        if detected == "PLATER" then
            local prof = _G.Plater and _G.Plater.db and _G.Plater.db.profile
            local pc = prof and prof.plate_config and prof.plate_config.enemynpc
            if pc then
                -- Plater stores each bar as a {width, height} array, split into
                -- in-combat / out-of-combat variants. In-combat is the
                -- dungeon-representative one.
                local h = pc.health_incombat or pc.health
                if type(h) == "table" then hw = h[1]; hh = h[2] end
                local c = pc.cast_incombat or pc.cast
                if type(c) == "table" then cw = c[1]; ch = c[2] end
            end
        elseif detected == "EUI" then
            local ns = _G.EllesmereNameplates_NS
            local prof = ns and ns.db and ns.db.profile
            if prof then
                -- EUI stores health width as an OFFSET added to a 150px base;
                -- the cast bar mirrors the health width.
                local barW = tonumber(prof.healthBarWidth)
                if barW then hw = 150 + barW end
                hh = prof.healthBarHeight
                cw = hw
                ch = prof.castBarHeight
            end
        end
    end)
    if not ok then return nil end
    return saneW(hw), saneH(hh), saneW(cw), saneH(ch)
end

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

    -- A scaled container holds the whole sample (plate + icon row) so it can be
    -- enlarged as one unit while keeping every proportion exact. plate + marker
    -- are its children; only the stage is reparented to the live GUI host.
    local stage = self._npPreviewStage
    if not stage then
        stage = CreateFrame("Frame", nil, host)
        stage:SetSize(1, 1)
        self._npPreviewStage = stage
    end
    stage:SetParent(host)
    stage:ClearAllPoints()
    stage:SetPoint("CENTER", host, "CENTER", 0, 0)
    stage:Show()

    local plate = self._npPreviewPlate
    if not plate then
        -- `plate` IS the health bar (the marker anchors to it, mirroring the live
        -- resolvePlateAnchor result). A name + HP text inside the bar and a cast
        -- bar below turn the bare bar into a representative modern nameplate
        -- (Plater/EUI/Platynator style) so the icon placement preview reads
        -- against something realistic.
        plate = CreateFrame("Frame", nil, stage)
        plate.border = plate:CreateTexture(nil, "BACKGROUND")
        plate.border:SetAllPoints(plate)
        plate.border:SetColorTexture(0, 0, 0, 1)
        plate.fill = plate:CreateTexture(nil, "ARTWORK")
        plate.fill:SetPoint("TOPLEFT", 1, -1)
        plate.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        plate.fill:SetColorTexture(0.851, 0.816, 0.588, 1)  -- health bar (#d9d096)
        -- Subtle top sheen so the bar reads as a health bar, not a flat block.
        plate.sheen = plate:CreateTexture(nil, "OVERLAY")
        plate.sheen:SetColorTexture(1, 1, 1, 0.10)
        plate.sheen:SetPoint("TOPLEFT", plate.fill, "TOPLEFT", 0, 0)
        plate.sheen:SetPoint("RIGHT", plate.fill, "RIGHT", 0, 0)
        plate.sheen:SetHeight(2)

        -- HP text (right, inside the bar) — created first so the name can bound
        -- itself against it. A generic stand-in value, no live health implied.
        plate.hp = plate:CreateFontString(nil, "OVERLAY")
        if KE.ApplyFontToText then KE:ApplyFontToText(plate.hp, "Expressway", 13, "OUTLINE") end
        plate.hp:SetTextColor(1, 1, 1)
        plate.hp:SetText("23M | 100%")
        plate.hp:SetJustifyH("RIGHT")
        plate.hp:SetPoint("RIGHT", plate, "RIGHT", -4, 0)

        -- Mob name (left, inside the bar). Width-bounded against the HP text and
        -- word-wrap off, so a long name truncates with an ellipsis like the live
        -- plate does. A generic stand-in — no specific mob implied.
        plate.name = plate:CreateFontString(nil, "OVERLAY")
        if KE.ApplyFontToText then KE:ApplyFontToText(plate.name, "Expressway", 13, "OUTLINE") end
        plate.name:SetTextColor(1, 1, 1)
        plate.name:SetText("Cznfik")
        plate.name:SetJustifyH("LEFT")
        plate.name:SetWordWrap(false)
        plate.name:SetPoint("LEFT", plate, "LEFT", 4, 0)
        plate.name:SetPoint("RIGHT", plate.hp, "LEFT", -6, 0)

        -- Cast bar below: icon + interruptible-gold fill + label — the exact
        -- context a trash CAST tracker sits beside. Static (no live timing).
        local cast = CreateFrame("Frame", nil, plate)
        cast:SetPoint("TOP", plate, "BOTTOM", 0, -1)
        cast.border = cast:CreateTexture(nil, "BACKGROUND")
        cast.border:SetAllPoints(cast)
        cast.border:SetColorTexture(0, 0, 0, 1)
        cast.bg = cast:CreateTexture(nil, "BORDER")
        cast.bg:SetPoint("TOPLEFT", 1, -1)
        cast.bg:SetPoint("BOTTOMRIGHT", -1, 1)
        cast.bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
        cast.icon = cast:CreateTexture(nil, "ARTWORK")
        cast.icon:SetPoint("LEFT", cast, "LEFT", 1, 0)
        cast.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
        cast.icon:SetTexture("Interface\\Icons\\spell_shadow_shadowworddominate")
        cast.fill = cast:CreateTexture(nil, "ARTWORK")
        cast.fill:SetPoint("LEFT", cast.icon, "RIGHT", 2, 0)
        cast.fill:SetColorTexture(0.624, 0.749, 1.0, 1)  -- cast bar (#9fbfff)
        cast.spell = cast:CreateFontString(nil, "OVERLAY")
        if KE.ApplyFontToText then KE:ApplyFontToText(cast.spell, "Expressway", 11, "OUTLINE") end
        cast.spell:SetTextColor(1, 1, 1)
        cast.spell:SetText("Mind Control >> Cheekgripper       1.8")
        cast.spell:SetPoint("LEFT", cast.icon, "RIGHT", 5, 0)
        plate.cast = cast

        self._npPreviewPlate = plate
    end

    local marker = self._npPreviewMarker
    if not marker then
        marker = CreateFrame("Frame", nil, stage)
        marker:SetSize(1, 1)
        marker.icons = {}
        self._npPreviewMarker = marker
    end

    local detected = self:DetectNameplateAddon()
    local fp = PLATE_FOOTPRINTS[detected] or PLATE_FOOTPRINTS.BLIZZARD
    -- Real configured size where the addon exposes it (Plater/EUI), else the
    -- representative footprint. castW/castH stay nil unless the addon supplies
    -- them, in which case the cast bar below is derived from the health bar.
    local realHW, realHH, realCW, realCH = readAddonPlateSize(detected)
    local plateW = realHW or fp.w
    local plateH = realHH or fp.h
    plate:SetSize(plateW, plateH)
    plate:Show()

    -- Enlarge the whole sample to fill the card width (up to PREVIEW_MAX_SCALE),
    -- then centre the COMPOSITE, not just the plate, so the icons never spill off
    -- the edge. LEFT/RIGHT put the row beside the plate (fit plate + row, shift
    -- the plate away from the icons); TOP centres the row above (fit the wider of
    -- plate/row, no horizontal shift — the row is centred on the plate already).
    local isTop = (cfg.AnchorSide == "TOP")
    local iconSize = cfg.IconSize or 32
    local gap = cfg.Gap or 8
    local iconExtent = (cfg.ShowIcons ~= false) and (3 * iconSize + 3 * gap) or 0
    local avail = host:GetWidth()
    if not avail or avail < 60 then avail = 384 end
    local fitW = isTop and math_max(plateW, iconExtent) or (plateW + iconExtent)
    local scale = (avail - 16) / fitW
    if scale > PREVIEW_MAX_SCALE then scale = PREVIEW_MAX_SCALE end
    if scale < 0.75 then scale = 0.75 end
    stage:SetScale(scale)
    local dir = (cfg.AnchorSide == "LEFT") and 1 or -1  -- shift away from the icons
    local shiftX = isTop and 0 or (dir * iconExtent * 0.5)
    plate:ClearAllPoints()
    plate:SetPoint("CENTER", stage, "CENTER", shiftX, 0)

    -- Size the cast bar to the plate's width (its static anchors were set at
    -- creation); the icon is a square filling its height, the gold fill ~two
    -- thirds of the remaining room.
    local cast = plate.cast
    local castW = realCW or plateW
    local castH = realCH or math_max(11, math_floor(plateH * 0.8 + 0.5))
    cast:SetSize(castW, castH)
    cast.icon:SetSize(castH - 2, castH - 2)
    local castFillMax = math_max(1, castW - castH - 4)
    cast.fill:SetSize(math_floor(castFillMax * 0.66 + 0.5), castH - 2)

    if not cfg.ShowIcons then
        marker:Hide()
        for _, icon in ipairs(marker.icons) do icon:Hide() end
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

    return detected
end

-- Rebuild the sample from current config (called by every Nameplate setter).
function DTrash:RefreshNameplatePreview()
    local stage = self._npPreviewStage
    local host = stage and stage:GetParent()
    if host then self:BuildNameplatePreview(host) end
end

function DTrash:HideNameplatePreview()
    if self._npPreviewStage then self._npPreviewStage:Hide() end
    if self._npPreviewPlate then self._npPreviewPlate:Hide() end
    local marker = self._npPreviewMarker
    if marker then
        marker:Hide()
        for _, icon in ipairs(marker.icons) do icon:Hide() end
    end
end

return DTrash

-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer_HUD.lua                                 ║
-- ║  Render + layout for the M+ Timer HUD. Pure function of  ║
-- ║  MPT.run -> frame visuals. No WoW API reads here.        ║
-- ║  Visual structure ported from WarpDeplete Render.lua;    ║
-- ║  timer/threshold/bar layout from EllesmereUIMythicTimer. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end
local MPT = KitnEssentials:GetModule("MythicPlusTimer")

local CreateFrame = CreateFrame
local floor = math.floor
local min, max, abs = math.min, math.max, math.abs  -- max/abs used here; min used by RenderBar
local format = string.format

-- Color array → "|cffRRGGBB" prefix (used by RenderObjectives per-row).
-- floor already declared above; do NOT re-declare it.
local function Hex(c)
    return format("|cff%02x%02x%02x", floor((c[1] or 1) * 255), floor((c[2] or 1) * 255), floor((c[3] or 1) * 255))
end

-- "MM:SS" with the leading zero stripped ("04:14" -> "4:14"). Used by the
-- threshold labels and both deaths parts (headline penalty + tooltip rows);
-- the big timer keeps the padded form. Declared above BuildHUD so the
-- tooltip's OnEnter closure can see it.
local function _FmtShort(sec)
    return (MPT.FormatTime(sec, false):gsub("^0", "", 1))
end

-- Objective-row frame pool (Step 1 of Task 3.2).
-- Each kit = { row, name, time } where row is the root Frame and
-- name/time are the left/right FontStrings. Scripts and font structure
-- are wired once inside the factory; per-render state is set in
-- RenderObjectives. The resetter hides both FontStrings and clears any
-- PBOpacity alpha dim so the kit is safe for reuse.
MPT._objRowPool = MPT._objRowPool or KE.FramePool:New(
    function(holder)
        local row = CreateFrame("Frame", nil, holder)
        local nameFS = row:CreateFontString(nil, "OVERLAY")
        nameFS:SetWordWrap(false)
        nameFS:SetNonSpaceWrap(false)
        nameFS:SetJustifyH("RIGHT")  -- whole HUD is right-aligned (user design)
        local timeFS = row:CreateFontString(nil, "OVERLAY")
        timeFS:SetWordWrap(false)
        timeFS:SetNonSpaceWrap(false)
        timeFS:SetJustifyH("RIGHT")
        return { row = row, name = nameFS, time = timeFS }
    end,
    function(kit)
        kit.name:Hide()
        kit.time:Hide()
        kit.time:SetAlpha(1)  -- clear any PBOpacity dim before reuse (FontString alpha persists across Hide/Show)
    end
)

-- Reusable buffer for ApplyLayout's length-gate signature (avoids a transient
-- table allocation each time the gate is checked).
local _sigBuf = {}

-- Gap (px) on each side of the big timer's "/" separator — roughly half a
-- space glyph at the default 28px timer font. 2026-06-10 round-3 feedback:
-- pull both the elapsed and total sides inward toward the separator.
local TIMER_SEP_GAP = 3

---------------------------------------------------------------------------------
-- Gating helpers (module functions — not methods; take widget explicitly)
---------------------------------------------------------------------------------

-- Skip SetText when the string is identical to the prior tick (safe here:
-- all strings derive from non-secret values per spec §8).
-- _keLast is stamped AFTER SetText: if SetText throws (e.g. "Font not set"
-- on a not-yet-fonted FontString), a pre-stamped cache would make every
-- later render skip the retry and the text would stay blank for the session.
function MPT.SetTextGated(fs, str)
    if not fs then return end
    str = str or ""
    if fs._keLast == str then return end
    fs:SetText(str)
    fs._keLast = str
end

-- Skip SetTextColor when the color is unchanged. Renders recolor on every
-- tick; the color only actually changes at run start / overtime / completion.
function MPT.SetColorGated(fs, r, g, b)
    if not fs then return end
    if fs._keLastR == r and fs._keLastG == g and fs._keLastB == b then return end
    fs._keLastR, fs._keLastG, fs._keLastB = r, g, b
    fs:SetTextColor(r, g, b)
end

-- Skip SetValue when the new fill differs from the last by < 1 physical
-- pixel of the bar's pixel width. widthPx = bar width in addon coords;
-- falls back to bar:GetWidth() so the gate never silently disappears
-- when a caller omits it (DT `_cachedBarWidth or GetWidth()` pattern).
function MPT.SetValueGated(bar, v, widthPx)
    if not bar then return end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    local w = widthPx or bar:GetWidth()
    local last = bar._keLastValue
    if last and w and w > 0 and abs(v - last) * w < 1 then return end
    bar._keLastValue = v
    bar:SetValue(v)
end

---------------------------------------------------------------------------------
-- BuildHUD — create all frames, fontstrings, bars, and tick textures (once)
---------------------------------------------------------------------------------

function MPT:BuildHUD()
    if self.frames and self.frames.root then return end
    self.frames = self.frames or {}

    local root = CreateFrame("Frame", "KE_MythicPlusTimer", UIParent, "BackdropTemplate")
    root:SetSize(300, 200)
    -- Build-time default only — ApplySettings (Task 2.5) must re-apply Strata
    -- (and bar textures) so GUI changes take effect without a /reload.
    root:SetFrameStrata(self.db and self.db.Strata or "MEDIUM")
    root:SetClampedToScreen(true)
    root:EnableMouse(false)
    self.frames.root = root

    -- Backdrop texture (transparent by default; recolored in ApplyLayout
    -- from BackdropEnabled/BackdropColor/BackdropOpacity).
    root.bgTex = root:CreateTexture(nil, "BACKGROUND")
    root.bgTex:SetAllPoints(root)
    root.bgTex:SetColorTexture(0, 0, 0, 0)

    -- Bars container (child of root; holds the two StatusBars + ticks).
    local bars = CreateFrame("Frame", "KE_MythicPlusTimerBars", root)
    self.frames.bars = bars

    -- Text overlay: bar-adjacent text (forces %, threshold labels) lives on a
    -- child frame leveled ABOVE the bar frames. FontStrings on root's own
    -- draw layers render beneath child frames regardless of layer, so text
    -- that overlaps a bar (CENTER forces placement, INSIDE threshold labels)
    -- would otherwise vanish behind the bar textures.
    local textOverlay = CreateFrame("Frame", nil, root)
    textOverlay:SetAllPoints(root)
    textOverlay:SetFrameLevel(root:GetFrameLevel() + 10)
    root.textOverlay = textOverlay

    -- FontString factory: text lives on root (contract §Frames rule) except
    -- the bar-adjacent strings, which take the overlay as an explicit parent.
    local function FS(layer, parent)
        local fs = (parent or root):CreateFontString(nil, layer or "ARTWORK")
        fs:SetWordWrap(false)
        fs:SetNonSpaceWrap(false)
        -- Seed a real font at creation (EnsureRows pattern): ApplyLayout's
        -- per-element fonts land on the DEFERRED first layout pass, but
        -- Render's SetText calls run synchronously before it — a template-
        -- less FontString with no font errors "Font not set" on SetText
        -- (hit via ShowPreview's first Render of a fresh session).
        KE:ApplyFont(fs, (self.db and self.db.FontFace) or "Expressway",
            (self.db and self.db.FontSize) or 13, "OUTLINE")
        return fs
    end

    root.deathsText    = FS()              -- "N Deaths (+penalty)"
    root.timerText     = FS()              -- changing timer part ("15:00")
    root.timerSepText  = FS()              -- static "/" separator (own FS so both side-gaps are anchor-tunable)
    root.timerSuffixText = FS()            -- static total ("28:00"), pinned at the right edge
    root.timerPBText   = FS()              -- gold PB beside timer (countdown)
    root.keyText       = FS()              -- "[30]" key bracket
    root.affixText     = FS()              -- affix names (TEXT mode)
    root.affixIcons    = {}                -- ICON-mode textures (lazy, Task 2.4)
    root.thresh3Text   = FS(nil, textOverlay)  -- remaining label at +3 tick
    root.thresh2Text   = FS(nil, textOverlay)  -- remaining label at +2 tick
    root.thresh1Text   = FS(nil, textOverlay)  -- remaining label at +1 (bar end)
    root.forcesText    = FS(nil, textOverlay)  -- forces percent/count text

    root.timerPBText:SetPoint("RIGHT", root.timerText, "LEFT", -4, 0)  -- rendered in Task 3.7 (gold PB)

    local barTex = KE:GetStatusbarPath(self.db and self.db.BarTexture or "KitnUI")

    -- Timer bar (BackdropTemplate wrapper + inset StatusBar; KickTracker pattern)
    local timerWrap = CreateFrame("Frame", nil, bars, "BackdropTemplate")
    timerWrap:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    timerWrap:SetBackdropBorderColor(0, 0, 0, 1)
    local timerBar = CreateFrame("StatusBar", nil, timerWrap)
    timerBar:SetPoint("TOPLEFT", timerWrap, "TOPLEFT", 1, -1)
    timerBar:SetPoint("BOTTOMRIGHT", timerWrap, "BOTTOMRIGHT", -1, 1)
    timerBar:SetStatusBarTexture(barTex)
    timerBar:SetMinMaxValues(0, 1)
    timerBar:SetValue(0)
    local timerBg = timerBar:CreateTexture(nil, "BACKGROUND")
    timerBg:SetAllPoints()
    timerBg:SetTexture(barTex)
    timerBg:SetVertexColor(0.031, 0.031, 0.031, 0.8)
    bars.timerWrap, bars.timerBar, bars.timerBg = timerWrap, timerBar, timerBg

    -- Two pixel-snapped tick marks on the timer bar (at +3 / +2 cutoffs).
    -- Parented to the timer StatusBar so they ride its anchor (EUI _seg3/_seg2).
    bars.tick3 = timerBar:CreateTexture(nil, "OVERLAY")
    bars.tick2 = timerBar:CreateTexture(nil, "OVERLAY")

    -- Forces bar (same wrapper/inset pattern as the timer bar)
    local forcesWrap = CreateFrame("Frame", nil, bars, "BackdropTemplate")
    forcesWrap:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    forcesWrap:SetBackdropBorderColor(0, 0, 0, 1)
    local forcesBar = CreateFrame("StatusBar", nil, forcesWrap)
    forcesBar:SetPoint("TOPLEFT", forcesWrap, "TOPLEFT", 1, -1)
    forcesBar:SetPoint("BOTTOMRIGHT", forcesWrap, "BOTTOMRIGHT", -1, 1)
    forcesBar:SetStatusBarTexture(barTex)
    forcesBar:SetMinMaxValues(0, 1)
    forcesBar:SetValue(0)
    local forcesBg = forcesBar:CreateTexture(nil, "BACKGROUND")
    forcesBg:SetAllPoints()
    forcesBg:SetTexture(barTex)
    forcesBg:SetVertexColor(0.031, 0.031, 0.031, 0.8)
    bars.forcesWrap, bars.forcesBar, bars.forcesBg = forcesWrap, forcesBar, forcesBg

    -- Pull-preview hook: DEAD on 12.0 — per-unit forces progress is secret
    -- (memory: project_warpdeplete_forces_preview_blocked; aggregate criteria
    -- are kill-credited only). Created hidden, never fed data, gated by
    -- db.ShowPullOverlay (defaults false, Task 0.2); GUI exposes nothing in
    -- Phase 1. If a future 12.x de-secrets per-unit forces, implement the
    -- engaged-but-unkilled feed here.
    bars.forcesPullOverlay = forcesBar:CreateTexture(nil, "ARTWORK")
    bars.forcesPullOverlay:SetColorTexture(1, 1, 1, 0.35)
    bars.forcesPullOverlay:Hide()

    -- Deaths hover hit-frame (built once). The headline FontString is
    -- MPT.frames.root.deathsText (created above).
    MPT.frames.deathsHit = CreateFrame("Frame", nil, MPT.frames.root)
    MPT.frames.deathsHit:SetFrameLevel(MPT.frames.root:GetFrameLevel() + 5)
    MPT.frames.deathsHit:EnableMouse(true)

    -- Custom two-column death tooltip (class-colored name LEFT, death-time RIGHT).
    -- Ported from EllesmereUIMythicTimer.lua:906-931 with KE transformations:
    --   * BackdropTemplate so SetBackdrop is available (KE:ApplyBackdrop requires it)
    --   * KE:ApplyBackdrop replaces EllesmereUI.MakeBorder (Enabled=true is load-bearing)
    --   * KE.FONT replaces EllesmereUI.EXPRESSWAY
    --   * "time" column replaces "count" column (timestamped per-death, not aggregated count)
    -- Grow-only EnsureRows cache retained deliberately: row count is bounded by
    -- party size × deaths; the tooltip is transient; verbatim EUI port is lower-risk
    -- than adopting KE.FramePool (acknowledged deviation from spec §11).
    local deathTT = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    deathTT:SetFrameStrata("TOOLTIP")
    deathTT:SetFrameLevel(200)
    deathTT:SetClampedToScreen(true)  -- cursor-left anchor near the screen edge
    deathTT:Hide()
    -- Near-black @ 0.8 — matches the bars' empty-track tint (#080808; the
    -- solid 0.9 black read too harsh against the HUD, round-6 feedback).
    KE:ApplyBackdrop(deathTT, { Enabled = true, Color = {0.031, 0.031, 0.031, 0.8}, BorderColor = {0, 0, 0, 1}, BorderSize = 1 })
    deathTT._rows = {}
    MPT.frames.deathsTooltip = deathTT

    local TT_PAD   = 8
    local TT_GAP   = 3
    local TT_FONT  = KE.FONT or "Fonts\\FRIZQT__.TTF"  -- EnsureRows seed; OnEnter re-applies the Deaths font

    local function EnsureRows(n)
        for i = #deathTT._rows + 1, n do
            local nameFS = deathTT:CreateFontString(nil, "OVERLAY")
            nameFS:SetFont(TT_FONT, 10, "")
            nameFS:SetJustifyH("LEFT")
            local timeFS = deathTT:CreateFontString(nil, "OVERLAY")
            timeFS:SetFont(TT_FONT, 10, "")
            timeFS:SetJustifyH("RIGHT")
            deathTT._rows[i] = { name = nameFS, time = timeFS }
        end
    end

    MPT.frames.deathsHit:SetScript("OnEnter", function()
        if not MPT.db or not MPT.db.ShowDeathTooltip then return end
        local log = MPT.run and MPT.run.deathLog
        if not log or #log == 0 then return end

        -- Scale the tooltip rows with the Deaths font settings (round-4
        -- feedback: the hardcoded 10px rows read far too small). Rows match
        -- the headline size exactly — the earlier +2 read too large once the
        -- rest of the tooltip was fixed (round-6 feedback).
        local ttFace = MPT.db.DeathsFontFace or MPT.db.FontFace
        local ttSize = MPT.db.DeathsFontSize or MPT.db.FontSize or 13
        local rowH   = ttSize + 4

        -- Build sorted list (chronological by time-of-death).
        local list = {}
        for i = 1, #log do
            list[i] = log[i]
        end
        -- Tiebreak on name so equal-second deaths keep a stable row order.
        table.sort(list, function(a, b)
            if a.t ~= b.t then return a.t < b.t end
            return (a.name or "") < (b.name or "")
        end)

        EnsureRows(#list)

        -- Hide all rows first.
        for i = 1, #deathTT._rows do
            deathTT._rows[i].name:Hide()
            deathTT._rows[i].time:Hide()
        end

        -- Measure max name and time widths for tooltip sizing.
        local maxNameW = 0
        local maxTimeW = 0
        for i, entry in ipairs(list) do
            local row = deathTT._rows[i]
            -- Re-apply per show: EnsureRows seeds 10px; the user can change
            -- the Deaths font card while the tooltip rows already exist.
            KE:ApplyFont(row.name, ttFace, ttSize, "")
            KE:ApplyFont(row.time, ttFace, ttSize, "")
            local class = entry.class
            local color = class and RAID_CLASS_COLORS[class]
            local short = Ambiguate(entry.name or "", "short")
            local colored = color and color:WrapTextInColorCode(short) or short
            row.name:SetText(colored)
            row.name:SetTextColor(1, 1, 1, 0.80)
            local timeStr = _FmtShort(entry.t)  -- "3:44", not "03:44" (round-6 feedback)
            row.time:SetText(timeStr)
            row.time:SetTextColor(1, 1, 1, 0.80)
            local nw = row.name:GetStringWidth() or 0
            local tw = row.time:GetStringWidth() or 0
            if nw > maxNameW then maxNameW = nw end
            if tw > maxTimeW then maxTimeW = tw end
        end

        local ttW = TT_PAD + maxNameW + 12 + maxTimeW + TT_PAD
        local ttH = TT_PAD + #list * rowH + (#list - 1) * TT_GAP + TT_PAD
        deathTT:SetSize(ttW, ttH)

        -- Position rows.
        for i, _ in ipairs(list) do
            local row = deathTT._rows[i]
            local yOff = -TT_PAD - (i - 1) * (rowH + TT_GAP)
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", deathTT, "TOPLEFT", TT_PAD, yOff)
            row.time:ClearAllPoints()
            row.time:SetPoint("TOPRIGHT", deathTT, "TOPRIGHT", -TT_PAD, yOff)
            row.name:Show()
            row.time:Show()
        end

        -- Anchor LEFT of the cursor (round-6 feedback — anchored above the
        -- deaths line it sat on top of the HUD). Placed once per OnEnter;
        -- GetCursorPosition returns physical px, so divide by the UIParent
        -- scale to land in frame coordinates.
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        deathTT:ClearAllPoints()
        deathTT:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", cx / s - 10, cy / s)
        deathTT:Show()
    end)

    MPT.frames.deathsHit:SetScript("OnLeave", function()
        deathTT:Hide()
    end)

    root:Hide()

    -- Defensive: if BuildHUD was called lazily (e.g. from Render after OnEnable),
    -- register with EditMode now. Idempotent via self.editModeRegistered guard.
    -- Mirrors KickTracker's pattern (KickTracker.lua:1282).
    if self.RegWithEditMode then self:RegWithEditMode() end
end

---------------------------------------------------------------------------------
-- RenderTimer — format elapsed/limit into one of five display strings and
-- recolor the FontString: white while running, gold on timed completion,
-- red when depleted (elapsed > limit or run completed past limit).
-- Design: uniform white (no separate gray "/ limit") per user direction.
-- FormatTime resolved lazily to be load-order-safe (Phase 1 assigns it after
-- this file parses).
---------------------------------------------------------------------------------

function MPT:RenderTimer()
    local run, db = self.run, self.db
    local f = self.frames and self.frames.root
    if not f or not db then return end
    local FormatTime = MPT.FormatTime
    local elapsed = run.elapsed or 0
    local maxTime = run.maxTime or 0
    local timeLeft = max(0, maxTime - elapsed)

    local elaStr = FormatTime(elapsed, false)
    local maxStr = FormatTime(maxTime, false)
    local remStr = FormatTime(timeLeft, false)
    local mode = db.TimerFormat or "ELAPSED_TOTAL"

    -- On completion, freeze elapsed from the authoritative completion time
    -- and optionally render milliseconds (spec §6.1 / §8).
    if run.completed then
        if db.ShowMilliseconds then
            elaStr = FormatTime(elapsed, true)   -- run.elapsed already = completionInfo.time/1000 (Phase 1)
        end
    end

    -- Split into a changing part and a STATIC "/" + total rendered by their
    -- own right-pinned FontStrings: re-measuring the combined string every
    -- second made the whole line shimmer (proportional digit widths + width
    -- rounding). The static side never re-renders, so it is pixel-stable;
    -- only the changing part's left edge moves. The separator is its own FS
    -- so both side-gaps come from anchor offsets (TIMER_SEP_GAP) instead of
    -- full space glyphs — tighter against the "/" per round-3 feedback.
    -- DETAIL's tail changes per tick, so it stays whole-string (suffix empty).
    local str, suffix
    if mode == "REMAINING" then
        str, suffix = remStr, ""
    elseif mode == "REMAINING_TOTAL" then
        str, suffix = remStr, maxStr
    elseif mode == "ELAPSED" then
        str, suffix = elaStr, ""
    elseif mode == "ELAPSED_DETAIL" then
        -- e.g. "21:23 (11:37 / 33:00)" — elapsed (remaining / total)
        str, suffix = elaStr .. " (" .. remStr .. " / " .. maxStr .. ")", ""
    else -- ELAPSED_TOTAL (default)
        str, suffix = elaStr, maxStr
    end

    -- Default: white from db.TimerColor.
    -- Completion: gold if timed, red if depleted.
    -- Running past limit (elapsed > maxTime): red immediately.
    local r, g, b = db.TimerColor[1], db.TimerColor[2], db.TimerColor[3]
    if run.completed then
        local timed = (run.maxTime > 0) and (elapsed <= run.maxTime)
        local c = timed and db.TimerSuccessColor or db.TimerExpiredColor
        r, g, b = c[1], c[2], c[3]
    elseif maxTime > 0 and timeLeft <= 0 then
        local c = db.TimerExpiredColor
        r, g, b = c[1], c[2], c[3]
    end

    self.SetTextGated(f.timerText, str)
    self.SetColorGated(f.timerText, r, g, b)
    f.timerText:Show()
    self.SetTextGated(f.timerSuffixText, suffix)
    if suffix ~= "" then
        self.SetTextGated(f.timerSepText, "/")
        self.SetColorGated(f.timerSuffixText, r, g, b)
        self.SetColorGated(f.timerSepText, r, g, b)
        f.timerSuffixText:Show()
        f.timerSepText:Show()
    else
        -- Single-value modes: ApplyLayout anchors timerText straight to the
        -- frame edge when the suffix is hidden (no separator-gap drift).
        self.SetTextGated(f.timerSepText, "")
        f.timerSuffixText:Hide()
        f.timerSepText:Hide()
    end

    -- Overall PB / delta beside the timer (f.timerPBText: created + anchored
    -- in Task 2.1; fonted by ApplyLayout's applyFont(f.timerPBText, "PB")).
    if MPT.run.completed and MPT.run.bestOverall then
        -- Completion: signed overall delta vs the pre-run PB.
        local diff = (MPT.run.elapsed or 0) - MPT.run.bestOverall
        local col = diff <= 0 and (MPT.db.SplitAheadColor or {0.25, 0.88, 0.82})
                              or (MPT.db.SplitBehindColor or {1, 0.42, 0.42})
        local sign = diff < 0 and "-" or "+"
        local dStr = (diff == 0) and "0:00" or MPT.FormatTime(abs(diff), false)
        MPT.SetTextGated(f.timerPBText, format("%s%s%s|r", Hex(col), sign, dStr))
        f.timerPBText:SetAlpha(1)
        f.timerPBText:Show()
    elseif MPT.run.bestOverall then
        -- Countdown AND live run: keep the gold overall PB visible.
        local pbHex = Hex(MPT.db.PBColor or {0.85, 0.79, 0.54})
        local a = max(0, min(1, MPT.db.PBOpacity or 1))
        -- Fallback source tag (WD GetBestSplit sourceLevel parity): when the
        -- record came from a DIFFERENT key level, show which one you're
        -- racing — "PB 25:30 [11]" on a 12. Exact-level records stay clean.
        -- One tag on the overall line only; the per-boss gold targets come
        -- from the same whole-record resolve, so it speaks for all of them.
        local src = MPT.run.pbSourceLevel
        local tag = (src and src ~= (MPT.run.level or 0)) and format(" [%d]", src) or ""
        local pbStr = format("%sPB %s%s|r", pbHex, MPT.FormatTime(MPT.run.bestOverall, false), tag)
        MPT.SetTextGated(f.timerPBText, pbStr)
        f.timerPBText:SetAlpha(a)
        f.timerPBText:Show()
    else
        f.timerPBText:Hide()
    end
end

---------------------------------------------------------------------------------
-- StateFillColor — file-local; maps elapsed bands to EUI's state palette.
-- Ported from EllesmereUI GetTimerBarFillColor (lines 213-223); uses
-- precomputed run.thresholds instead of recomputing inside the render path.
---------------------------------------------------------------------------------

local function StateFillColor(elapsed, thresholds)
    local t2, t3 = thresholds.plus2, thresholds.plus3
    if elapsed > t2 then
        return 0xB0/255, 0x59/255, 0xCC/255   -- +2 lost: purple
    elseif elapsed > t3 then
        return 0.30, 0.80, 1.00               -- +3 lost, +2 on: blue
    end
    return 0.40, 1.00, 0.40                   -- on for +3: green
end

---------------------------------------------------------------------------------
-- RenderBar — single timer-bar fill. Default: neutral db.BarColor. Optional
-- db.StateColorFill: EUI state palette (green/blue/purple) that persists at
-- completion. Neutral default recolors gold (timed) / red (depleted) on
-- completion (spec §6.2). SetValueGated used for pixel-aware skipping.
---------------------------------------------------------------------------------

function MPT:RenderBar()
    local run, db = self.run, self.db
    local bars = self.frames and self.frames.bars
    if not bars or not db then return end
    local bar = bars.timerBar
    local maxTime = run.maxTime or 0
    if maxTime <= 0 then
        -- Reset fill so a stale bar never lingers when a new run has no data yet.
        MPT.SetValueGated(bar, 0)
        return
    end

    local elapsed = run.elapsed or 0
    local fillPct = min(1, elapsed / maxTime)

    local widthPx = bars.timerWrap:GetWidth() or (db.BarWidth or 300)
    self.SetValueGated(bar, fillPct, widthPx)

    local r, g, b
    if db.StateColorFill then
        -- EUI behavior: state color persists at completion (run.elapsed is
        -- already frozen to the authoritative completion time by CompleteRun).
        r, g, b = StateFillColor(elapsed, run.thresholds)
    elseif run.completed then
        -- Spec §6.2: neutral default fill recolors at completion
        -- (gold = timed, red = depleted).
        local timed = (maxTime > 0) and (elapsed <= maxTime)
        local c = timed and db.TimerSuccessColor or db.TimerExpiredColor
        r, g, b = c[1], c[2], c[3]
    else
        r, g, b = db.BarColor[1], db.BarColor[2], db.BarColor[3]
    end

    -- Gate the recolor: SetStatusBarColor is a draw call; skip when unchanged.
    if bar._keFillR ~= r or bar._keFillG ~= g or bar._keFillB ~= b then
        bar._keFillR, bar._keFillG, bar._keFillB = r, g, b
        bar:SetStatusBarColor(r, g, b)
    end
end

---------------------------------------------------------------------------------
-- _PlaceTick / _PlaceLabel — file-local helpers lifted out of RenderThresholds
-- so the geometry block (which now runs rarely) doesn't allocate closures.
-- Inline into the cache-miss block; label text still updates every tick below.
---------------------------------------------------------------------------------

-- Bracket wrapper for forces count/remaining text (NONE/SQUARE/ROUND).
-- Hoisted out of RenderForces so the closure is not re-created each tick.
local function _Brk(s, style)
    if style == "SQUARE" then return "[" .. s .. "]"
    elseif style == "ROUND" then return "(" .. s .. ")" end
    return s
end

local function _PlaceTick(tex, timerBar, barW, barH, tickW, cutoff, maxTime, tr, tg, tb)
    tex:ClearAllPoints()
    tex:SetSize(tickW, barH)
    local x = KE:PixelSnap(barW * (cutoff / maxTime)) - tickW / 2
    tex:SetPoint("TOPLEFT", timerBar, "TOPLEFT", x, 0)
    tex:SetColorTexture(tr, tg, tb, 1)
    tex:Show()
end

local function _PlaceLabel(fs, timerBar, barW, cutoff, maxTime, place)
    fs:ClearAllPoints()
    local x = KE:PixelSnap(barW * (cutoff / maxTime))
    if place == "INSIDE" then
        -- Fully on the bar, right-aligned just left of the tick; the +1
        -- label lands inside the bar's right end. Renders above the bar
        -- texture via the textOverlay parent.
        fs:SetPoint("RIGHT", timerBar, "LEFT", x - 3, 0)
    elseif place == "ABOVE" then
        -- Centered on the tick, fully above the bar.
        fs:SetPoint("BOTTOM", timerBar, "TOPLEFT", x, 2)
    else  -- EDGE (default): straddles the bar's TOP edge (WarpDeplete look) —
          -- label center ON the edge, half in / half out, left of its tick.
        fs:SetPoint("RIGHT", timerBar, "TOPLEFT", x - 3, 0)
    end
    fs:Show()
end

-- (_FmtShort — the leading-zero-stripped formatter these labels use — is
-- declared at the top of the file, above BuildHUD.)

-- Threshold label text: a live cutoff shows the remaining countdown; a missed
-- cutoff returns nil so the label hides (round-3 feedback — replaces the grey
-- absolute-time passed state from the EUI buildLabel port). The tick itself
-- stays visible permanently as a bar divider (round-3c feedback).
local function _ThreshLabel(elapsed, cutoff)
    if elapsed > cutoff then return nil end
    return _FmtShort(cutoff - elapsed)
end

-- Apply a threshold label: nil hides (passed cutoff), a string shows.
local function _SetThreshText(fs, label)
    if label then
        MPT.SetTextGated(fs, label)
        fs:Show()
    else
        MPT.SetTextGated(fs, "")
        fs:Hide()
    end
end

---------------------------------------------------------------------------------
-- RenderThresholds — pixel-snapped tick marks at +3/+2 cutoffs, and
-- remaining-time labels ABOVE the bar at +3/+2/+1 (WarpDeplete look).
-- Ticks: 2 physical pixels wide, db.TickColor, parented to timerBar.
-- Labels: gated on db.ShowThresholdLabels; use MPT.ThresholdRemaining.
--
-- Geometry (tick positions/sizes and label X-positions) is a pure function of
-- (barW, maxTime, thresholds, BarHeight, TickColor) — static for the duration
-- of a run. A signature cache on bars skips all ClearAllPoints/SetPoint/SetSize/
-- SetColorTexture calls when geometry is unchanged. Label TEXT (countdown
-- strings) still updates every tick outside the cache block.
-- NOTE: ApplySettings (Task 2.5) must set bars._keThreshSig = nil to bust this
-- cache when BarHeight or TickColor changes via the GUI.
---------------------------------------------------------------------------------

function MPT:RenderThresholds()
    local run, db = self.run, self.db
    local bars = self.frames and self.frames.bars
    if not bars or not db then return end
    local maxTime = run.maxTime or 0
    if maxTime <= 0 then
        bars.tick3:Hide(); bars.tick2:Hide()
        local f = self.frames.root
        if f then
            self.SetTextGated(f.thresh3Text, ""); f.thresh3Text:Hide()
            self.SetTextGated(f.thresh2Text, ""); f.thresh2Text:Hide()
            self.SetTextGated(f.thresh1Text, ""); f.thresh1Text:Hide()
        end
        return
    end

    local barW  = bars.timerWrap:GetWidth() or (db.BarWidth or 300)
    local barH  = (db.BarHeight or 14) - 2
    local tickW = KE:PixelSnap(2)
    local tr, tg, tb = db.TickColor[1], db.TickColor[2], db.TickColor[3]
    local t3 = run.thresholds.plus3
    local t2 = run.thresholds.plus2
    local t1 = run.thresholds.plus1
    local elapsed = run.elapsed or 0

    local place = db.ThresholdPlacement or "EDGE"

    -- Geometry cache: all SetPoint/SetSize/SetColorTexture calls are pure
    -- functions of this signature. Skip when nothing structural changed.
    local sig = barW .. ":" .. maxTime .. ":" .. t3 .. ":" .. t2 .. ":" .. t1 .. ":"
                .. (db.BarHeight or 14) .. ":" .. tr .. ":" .. tg .. ":" .. tb
                .. ":" .. place
    if bars._keThreshSig ~= sig then
        bars._keThreshSig = sig
        -- Ticks are PERMANENT dividers (round-3c feedback: a solid bar near
        -- the end looked off) — only the labels hide once a cutoff is missed.
        _PlaceTick(bars.tick3, bars.timerBar, barW, barH, tickW, t3, maxTime, tr, tg, tb)
        _PlaceTick(bars.tick2, bars.timerBar, barW, barH, tickW, t2, maxTime, tr, tg, tb)
        if db.ShowThresholdLabels then
            local f = self.frames.root
            _PlaceLabel(f.thresh3Text, bars.timerBar, barW, t3, maxTime, place)
            _PlaceLabel(f.thresh2Text, bars.timerBar, barW, t2, maxTime, place)
            _PlaceLabel(f.thresh1Text, bars.timerBar, barW, t1, maxTime, place)
        end
    end

    -- Remaining-time labels above the bar (WarpDeplete look).
    -- Text updates every tick regardless of geometry cache.
    local f = self.frames.root
    if not db.ShowThresholdLabels then
        self.SetTextGated(f.thresh3Text, ""); f.thresh3Text:Hide()
        self.SetTextGated(f.thresh2Text, ""); f.thresh2Text:Hide()
        self.SetTextGated(f.thresh1Text, ""); f.thresh1Text:Hide()
        return
    end
    _SetThreshText(f.thresh3Text, _ThreshLabel(elapsed, t3))
    _SetThreshText(f.thresh2Text, _ThreshLabel(elapsed, t2))
    -- The +1 (bar end) label keeps counting INTO the negative after the timer
    -- depletes ("-0:46" in the depleted color, round-3 feedback) instead of
    -- hiding like the passed +3/+2 cutoffs.
    local l1 = _ThreshLabel(elapsed, t1)
    if not l1 then
        local c = db.TimerExpiredColor or { 1, 0.16, 0.18 }
        l1 = Hex(c) .. "-" .. _FmtShort(elapsed - t1) .. "|r"
    end
    _SetThreshText(f.thresh1Text, l1)
end

---------------------------------------------------------------------------------
-- RenderKey — key level bracket + affix line (TEXT or ICON mode).
-- Steps 1-3 of Task 2.4.
--
-- Row layout (round-3 feedback: "[3] Lindormi's Guidance" — key LEFT of the
-- affixes): affixText is the row anchor at the frame's right edge, owned by
-- ApplyLayout's stacking pass even when hidden (ICON mode zeroes its text so
-- the rect collapses to the edge). keyText anchors LEFT of the affixes —
-- TEXT mode in ApplyLayout's config section; ICON mode re-anchored HERE after
-- the icon loop (icon count varies per run); affixes-off in the stacking
-- pass (row-anchored alone at the right edge).
--
-- ICON mode lazily builds holder frames into f.affixIcons[]. Each holder
-- wraps one texture; KE icon standard (ApplyIconZoom + AddIconBorders)
-- applied at construction time. Icons are sized to AffixFontSize + 4 px
-- and re-anchored each tick so a run-change (different affix count) stays
-- correct without a full rebuild.
--
-- Affix IDs are non-secret (spec §8 "key/affix/map metadata APIs") — no
-- issecretvalue guard applied.
---------------------------------------------------------------------------------

function MPT:RenderKey()
    local run, db = self.run, self.db
    local f = self.frames and self.frames.root
    if not f or not db then return end

    -- Key level bracket -------------------------------------------------------
    if not db.ShowKeyLevel then
        f.keyText:Hide()
    else
        self.SetTextGated(f.keyText, format("[%d]", run.level or 0))
        self.SetColorGated(f.keyText, db.KeyColor[1], db.KeyColor[2], db.KeyColor[3])
        f.keyText:Show()
    end

    -- Affixes — TEXT mode (default) -------------------------------------------
    if not db.ShowAffixes or db.AffixMode ~= "TEXT" then
        -- Zero the text, not just Hide: the hidden FontString is still the
        -- row's right-edge anchor (icons + key hang off its rect), so a stale
        -- string would offset them by its leftover width.
        self.SetTextGated(f.affixText, "")
        f.affixText:Hide()
    else
        self.SetTextGated(f.affixText, run.affixNamesStr or "")
        if db.AffixColor then
            self.SetColorGated(f.affixText, db.AffixColor[1], db.AffixColor[2], db.AffixColor[3])
        else
            self.SetColorGated(f.affixText, 0.69, 0.69, 0.69)
        end
        f.affixText:Show()
    end

    -- Affixes — ICON mode (optional) ------------------------------------------
    -- Icons are built lazily, sized to AffixFontSize+4, and grown leftward
    -- from keyText so they don't overflow the right edge of the backdrop.
    if db.AffixMode == "ICON" and db.ShowAffixes then
        local ids     = run.affixIDs     or {}
        local fileIDs = run.affixFileIDs or {}
        -- Same fallback chain as ApplyLayout's applyFont "Affix" prefix.
        local size = db.AffixFontSize or db.FontSize or 13
        local prev
        for i = 1, #ids do
            local fileID = fileIDs[i]
            if not fileID then
                -- Defensive: cached fileID missing (API returned nil at run start);
                -- hide this slot and skip so the rest of the icons still render.
                -- (No goto — WoW's runtime is Lua 5.1.)
                if f.affixIcons[i] then f.affixIcons[i]:Hide() end
            else
                local tex = f.affixIcons[i]
                if not tex then
                    local holder = CreateFrame("Frame", nil, f)
                    holder.tex = holder:CreateTexture(nil, "ARTWORK")
                    holder.tex:SetAllPoints(holder)
                    KE:ApplyIconZoom(holder.tex, 0.3)
                    KE:AddIconBorders(holder)
                    f.affixIcons[i] = holder
                    tex = holder
                end
                tex:SetSize(size + 4, size + 4)
                tex.tex:SetTexture(fileID)
                tex:ClearAllPoints()
                -- Grow leftward from the row's right-edge anchor (affixText,
                -- zero-width while hidden in ICON mode).
                if prev then
                    tex:SetPoint("RIGHT", prev, "LEFT", -4, 0)
                else
                    tex:SetPoint("TOPRIGHT", f.affixText, "TOPRIGHT", 0, 0)
                end
                tex:Show()
                prev = tex
            end
        end
        -- Hide any stale icons from a previous run with more affixes.
        for i = #ids + 1, #f.affixIcons do f.affixIcons[i]:Hide() end
        -- Key bracket rides LEFT of the icon row; icon count varies per run,
        -- so ICON mode owns this anchor here (TEXT mode: ApplyLayout).
        if db.ShowKeyLevel then
            f.keyText:ClearAllPoints()
            f.keyText:SetPoint("RIGHT", prev or f.affixText, "LEFT", prev and -4 or 0, 0)
        end
    elseif f.affixIcons then
        for i = 1, #f.affixIcons do f.affixIcons[i]:Hide() end
    end
end

---------------------------------------------------------------------------------
-- RenderDeaths — headline "N Deaths (+m:ss)" + hover tooltip (Task 3.5).
-- Replaces the Phase-2 headline-only stub wholesale.
--
-- Blank at 0 deaths (spec §7.1). Format: "N Deaths (+m:ss)" — penalty ADDS
-- to elapsed time (deliberate deviation from EUI's leading "-" sign).
-- Hit-frame is sized to the actual text so the hover region matches exactly.
-- Font/anchor owned by ApplyLayout (applyFont(f.deathsText, "Deaths") +
-- row(f.deathsText)); this render must not duplicate them.
-- SetTextGated: safe — deathTimeLost is plain math (spec §8 "GetDeathCount").
---------------------------------------------------------------------------------

function MPT:RenderDeaths()
    local db, run = MPT.db, MPT.run
    local fs, hit = MPT.frames.root.deathsText, MPT.frames.deathsHit
    if not db.ShowDeaths or (run.deaths or 0) <= 0 then
        fs:Hide(); hit:Hide()
        if MPT.frames.deathsTooltip then MPT.frames.deathsTooltip:Hide() end
        return
    end
    local dHex = Hex(db.DeathsColor or {0.85, 0.85, 0.85})
    local pHex = Hex(db.DeathPenaltyColor or {1, 0.42, 0.42})
    local str = format("%s%d Death%s|r %s(+%s)|r",
        dHex, run.deaths, run.deaths ~= 1 and "s" or "",
        pHex, _FmtShort(run.deathTimeLost or 0))
    MPT.SetTextGated(fs, str)
    fs:Show()
    -- Hit frame sized to the actual text so the hover region matches.
    -- (fs's anchor + font are owned by ApplyLayout, Task 2.5.)
    -- Geometry gated on the headline string — only re-measure when it changed.
    if hit._keForString ~= str then
        hit._keForString = str
        local tw = fs:GetStringWidth() or 0
        local th = fs:GetStringHeight() or (db.DeathsFontSize or db.FontSize or 13)
        hit:ClearAllPoints()
        hit:SetSize(tw, th)
        hit:SetPoint("TOPRIGHT", fs, "TOPRIGHT", 0, 0)
    end
    hit:Show()
end

---------------------------------------------------------------------------------
-- RenderForces — forces StatusBar fill + percent/count/custom text.
-- Step 5 of Task 2.4.
--
-- run.forces = { total, current, percent, completed } (plain math — no
-- issecretvalue guard per spec §8 "aggregate GetCriteriaInfo").
-- Fill = percent/100 via SetValueGated.
--
-- BAR color resolution order (highest wins last):
--   1. db.ForcesColor (base)
--   2. db.ForcesBandedColors (quintile palette; skipped at completion)
--   3. db.ForcesCompleteColor (wins unconditionally at completion)
-- The percent/count TEXT uses its own db.ForcesTextColor — independent of the
-- bar fill (2026-06-10 round-3 feedback: recoloring the bar dragged the text
-- along with it).
--
-- ForcesBandPalette bands: [1]=0-20%, [2]=20-40%, [3]=40-60%,
-- [4]=60-80%, [5]=80-100%, Full=exactly 100%.
--
-- Brk() wraps the count segment in brackets (NONE/SQUARE/ROUND).
-- CUSTOM format is exempt from Brk — the user owns the token string.
-- Lua 5.1 gsub replacement caveat: bare "%" is invalid; build the
-- formatted number then append "%%" (mirrors WarpDeplete Render.lua:732/735).
--
-- forcesText anchor: owned by ApplyLayout (Task 2.5, db.ForcesPlacement).
-- This function only sets text / color / visibility.
---------------------------------------------------------------------------------

function MPT:RenderForces()
    local run, db = self.run, self.db
    local bars = self.frames and self.frames.bars
    local f    = self.frames and self.frames.root
    if not bars or not f or not db then return end

    if not db.ShowForces then
        bars.forcesWrap:Hide(); f.forcesText:Hide(); return
    end
    bars.forcesWrap:Show()

    local fo = run.forces or {}
    local cur, total = fo.current or 0, fo.total or 0
    local pct = fo.percent or 0
    local widthPx = bars.forcesWrap:GetWidth() or (db.BarWidth or 300)
    self.SetValueGated(bars.forcesBar, min(1, pct / 100), widthPx)

    -- Color: banded quintile palette (opt-in) -> completion color wins last.
    local r, g, b = db.ForcesColor[1], db.ForcesColor[2], db.ForcesColor[3]
    if db.ForcesBandedColors and not fo.completed then
        local band = min(5, floor(pct / 20) + 1)
        local c = (pct >= 100 and db.ForcesBandPalette.Full) or db.ForcesBandPalette[band]
        if c then r, g, b = c[1], c[2], c[3] end
    end
    if fo.completed and db.ForcesCompleteColor then
        r, g, b = db.ForcesCompleteColor[1], db.ForcesCompleteColor[2], db.ForcesCompleteColor[3]
    end
    -- Gate the recolor: SetStatusBarColor is a draw call; skip when unchanged.
    local fb = bars.forcesBar
    if fb._keFillR ~= r or fb._keFillG ~= g or fb._keFillB ~= b then
        fb._keFillR, fb._keFillG, fb._keFillB = r, g, b
        fb:SetStatusBarColor(r, g, b)
    end

    local fmt = db.ForcesFormat or "PERCENT"
    local bs  = db.ForcesBracketStyle
    -- CUSTOM is exempt from _Brk — the user controls the token string directly.
    local str
    if fmt == "COUNT" then
        str = _Brk(format("%d/%d", floor(cur + 0.5), floor(total + 0.5)), bs)
    elseif fmt == "COUNT_PERCENT" then
        str = _Brk(format("%d/%d", floor(cur + 0.5), floor(total + 0.5)), bs) .. format(" - %.2f%%", pct)
    elseif fmt == "REMAINING" then
        str = _Brk(format("%d left", floor(max(0, total - cur) + 0.5)), bs)
    elseif fmt == "CUSTOM" then
        str = (db.ForcesCustomFormat or ":count:/:totalcount: :percent:")
        str = str:gsub(":count:", format("%d", floor(cur + 0.5)))
        str = str:gsub(":totalcount:", format("%d", floor(total + 0.5)))
        str = str:gsub(":remainingcount:", format("%d", floor(max(0, total - cur) + 0.5)))
        -- Bare "%" in a gsub replacement is invalid in Lua 5.1; build the
        -- formatted number first then append the literal "%" via "%%".
        str = str:gsub(":percent:", format("%.2f", pct) .. "%%")
        str = str:gsub(":remainingpercent:", format("%.2f", max(0, 100 - pct)) .. "%%")
    else -- PERCENT (default)
        str = format("%.2f%%", pct)
    end
    local tc = db.ForcesTextColor or { 1, 1, 1 }
    self.SetTextGated(f.forcesText, str)
    self.SetColorGated(f.forcesText, tc[1], tc[2], tc[3])
    f.forcesText:Show()
end

---------------------------------------------------------------------------------
-- RenderObjectives — pools one row per objective, positioned from
-- _objRowStartY downward (published by ApplyLayout). Writes _objRowEndY
-- (the only return channel to ApplyLayout for root-frame height).
--
-- Called FROM INSIDE ApplyLayout's stacking pass (not from Render).
-- ReleaseAll is at the top so surplus rows from a previous run vanish
-- immediately; the pool's hidden holder reparents them safely (no orphans).
--
-- Row format: name (left, engine-truncated) | [clearTime] ±delta OR PB target (right).
-- Completed rows:  ObjectiveDoneColor name + bracketed clear time + SplitAhead/BehindColor delta.
-- Pending rows:    ObjectiveColor name + PBColor "PB m:ss" at PBOpacity.
-- Zero objectives or ShowObjectives=false: _objRowEndY = _objRowStartY (no height consumed).
--
-- Secret-value note: clearTime/pbTime come from UpdateObjectives which reads
-- GetStepInfo (plain math per contract §62); no issecretvalue guard applied.
---------------------------------------------------------------------------------

function MPT:RenderObjectives()
    local db = MPT.db
    local run = MPT.run
    MPT._objRowPool:ReleaseAll()
    if not db.ShowObjectives then
        MPT._objRowEndY = MPT._objRowStartY  -- nothing consumed
        return
    end

    local root = MPT.frames.root
    local PAD = MPT._PAD or 12
    local frameW = root:GetWidth()
    local innerW = frameW - PAD * 2
    local oGap = MPT._OBJ_GAP or 4
    local y = MPT._objRowStartY or -PAD  -- set by ApplyLayout's vertical cursor

    local face    = db.ObjectiveFontFace    or db.FontFace
    local size    = db.ObjectiveFontSize    or db.FontSize    or 13
    local outline = db.ObjectiveFontOutline or db.FontOutline or "OUTLINE"

    local objectives = (run and run.objectives) or {}
    for i = 1, #objectives do
        local obj = objectives[i]
        local kit = MPT._objRowPool:Acquire(root)
        local nameFS, timeFS = kit.name, kit.time
        KE:ApplyFontToText(nameFS, face, size, outline)
        KE:ApplyFontToText(timeFS, face, size, outline)

        -- Name color: done = ObjectiveDoneColor, pending = ObjectiveColor.
        if obj.completed then
            local c = db.ObjectiveDoneColor or { 0.2, 0.82, 0.31 }
            nameFS:SetTextColor(c[1], c[2], c[3])
        else
            local c = db.ObjectiveColor or { 0.85, 0.85, 0.85 }
            nameFS:SetTextColor(c[1], c[2], c[3])
        end

        -- Count-based objectives (Pit of Saron "Quarry Camps" 0/6): prefix the
        -- name with the running count. Boss criteria are normalized to
        -- totalQuantity 1 in UpdateObjectives, so this gate skips them
        -- (EllesmereUIMythicTimer.lua:1675-1677 verbatim).
        local displayName = obj.name
        if obj.totalQuantity and obj.totalQuantity > 1 then
            displayName = format("%d/%d %s", obj.quantity or 0, obj.totalQuantity, displayName)
        end

        -- Right text: completed → [clear] + optional delta; pending → gold PB target.
        local rightText = ""
        if obj.completed and obj.clearTime and obj.clearTime > 0 then
            timeFS:SetAlpha(1)  -- clear a possible pending-row PBOpacity dim on this pooled slot
            -- "Show Clear Times" gates the [clear] bracket itself (EUI:1684);
            -- the PB delta is self-contained and independently gated below.
            if db.ShowObjectiveTimes ~= false then
                local doneHex = Hex(db.ObjectiveDoneColor or { 0.2, 0.82, 0.31 })
                rightText = format("%s[%s]|r", doneHex, MPT.FormatTime(obj.clearTime, false))
            end
            if db.ShowPBDelta and obj.pbTime then
                local diff = obj.clearTime - obj.pbTime
                local col  = diff <= 0 and (db.SplitAheadColor or { 0.25, 0.88, 0.82 })
                                       or  (db.SplitBehindColor or { 1, 0.42, 0.42 })
                local sign = diff < 0 and "-" or "+"
                local dStr = (diff == 0) and "0:00" or MPT.FormatTime(abs(diff), false)
                local sep  = (rightText ~= "") and "  " or ""
                rightText  = rightText .. sep .. format("%s(%s%s)|r", Hex(col), sign, dStr)
            end
        elseif (not obj.completed) and db.ShowUpcomingPB ~= false and obj.pbTime then
            -- Pending gold targets have their own toggle ("Show PB Targets") —
            -- ShowObjectiveTimes previously gated this branch by mistake,
            -- leaving the clear-time bracket itself ungated.
            local pbHex = Hex(db.PBColor or { 0.85, 0.79, 0.54 })
            local a = max(0, min(1, db.PBOpacity or 1))
            rightText = format("%sPB %s|r", pbHex, MPT.FormatTime(obj.pbTime, false))
            if a < 1 then timeFS:SetAlpha(a) else timeFS:SetAlpha(1) end
        end

        nameFS:ClearAllPoints()
        timeFS:ClearAllPoints()
        if rightText ~= "" then
            MPT.SetTextGated(timeFS, rightText)
            timeFS:SetTextColor(1, 1, 1)  -- 3-arg form (SOFTOUTLINE hook convention)
            timeFS:SetWidth(0)
            -- GetStringWidth is safe here: RenderObjectives runs only from the
            -- C_Timer.After(0) deferred layout path, never a tainted event handler.
            local timeW = timeFS:GetStringWidth() or 0
            timeFS:SetPoint("TOPRIGHT", root, "TOPRIGHT", -PAD, y)
            nameFS:SetPoint("TOPRIGHT", timeFS, "TOPLEFT", -4, 0)
            local nameMaxW = innerW - timeW - 4
            if nameMaxW < 20 then nameMaxW = 20 end
            nameFS:SetWidth(nameMaxW)
            timeFS:Show()
        else
            timeFS:Hide()
            nameFS:SetPoint("TOPRIGHT", root, "TOPRIGHT", -PAD, y)
            nameFS:SetWidth(innerW)
        end
        MPT.SetTextGated(nameFS, displayName)
        nameFS:Show()
        y = y - (nameFS:GetStringHeight() or size) - oGap
    end

    MPT._objRowEndY = y  -- ApplyLayout reads this to finalize the HUD height
end

---------------------------------------------------------------------------------
-- RequestLayout — deferred 1/frame batching (spec §11 "Deferred layout batching")
-- Collapses repeated layout requests into one C_Timer.After(0) pass; mirrors
-- KE's _RequestPositionUpdate pattern. A pending flag prevents stacking.
---------------------------------------------------------------------------------

-- Pre-declared: no closure allocation per RequestLayout call.
local function _ApplyLayoutFire()
    MPT._layoutPending = nil
    MPT:ApplyLayout()
end

function MPT:RequestLayout()
    if self._layoutPending then return end
    self._layoutPending = true
    C_Timer.After(0, _ApplyLayoutFire)
end

---------------------------------------------------------------------------------
-- ApplyLayout — owns ALL positioning (Layout-cursor contract §46-47).
-- Step 1: apply fonts to every FontString (per-element + global default).
-- Step 2: bar sizes, HUD anchor, scale, backdrop, straggler anchors.
-- Step 3: length-gated vertical relayout (Fabys trick) + objectives handoff.
-- Publishes: MPT._PAD, MPT._ROW_GAP, MPT._OBJ_GAP, MPT._objRowStartY.
-- Reads back: MPT._objRowEndY (written by RenderObjectives, Task 3.2).
---------------------------------------------------------------------------------

function MPT:ApplyLayout()
    if not self.frames or not self.frames.root then return end
    local db = self.db
    local f = self.frames.root

    -- Locals shared by both the config section and the stacking pass below.
    local PAD  = 12
    local ROW  = 2   -- tightened from 6 (2026-06-10 feedback: match WD's density)
    local barW = db.BarWidth  or 300
    local barH = db.BarHeight or 14
    local bars = self.frames.bars

    -- Config section: fonts, bar sizes, HUD anchor, scale, backdrop, straggler
    -- anchors.  Gated on f._keConfigDone so the nine ApplyFontToText calls and
    -- all SetSize/SetPoint/SetScale/SetColorTexture operations only fire when
    -- settings have actually changed (ApplySettings busts the flag).
    if not f._keConfigDone then
        f._keConfigDone = true

        -- Apply fonts (per-element fallback chain: <Element>FontFace/Size/Outline
        -- or global FontFace/Size/FontOutline). Pass LSM NAME — KE:ApplyFontToText
        -- resolves the path internally; never pre-resolve with GetFontPath here.
        local function applyFont(fs, prefix)
            local face    = db[prefix .. "FontFace"]    or db.FontFace
            local size    = db[prefix .. "FontSize"]    or db.FontSize    or 13
            local outline = db[prefix .. "FontOutline"] or db.FontOutline or "OUTLINE"
            KE:ApplyFontToText(fs, face, size, outline)
        end

        applyFont(f.deathsText,  "Deaths")
        applyFont(f.timerText,   "Timer")
        applyFont(f.timerSepText, "Timer")
        applyFont(f.timerSuffixText, "Timer")
        applyFont(f.timerPBText, "PB")
        applyFont(f.keyText,     "Key")
        applyFont(f.affixText,   "Affix")
        applyFont(f.thresh3Text, "Threshold")
        applyFont(f.thresh2Text, "Threshold")
        applyFont(f.thresh1Text, "Threshold")
        applyFont(f.forcesText,  "Forces")

        -- Bar sizes, HUD anchor, scale, backdrop recolor.
        f:SetWidth(barW + PAD * 2)
        bars.timerWrap:SetSize(barW, barH)
        bars.forcesWrap:SetSize(barW, barH)
        -- Height is load-bearing: a one-point + width-only frame has no
        -- resolvable rect, so WoW refuses to render every child anchored
        -- inside it (both bars, ticks, and the bar-relative threshold labels).
        bars:SetSize(barW, barH * 2 + ROW)

        f:SetScale(db.Scale or 1.0)

        -- KE:ApplyFramePosition sets frame strata internally from Config.Strata
        -- (Core/Globals.lua:651) — no separate SetFrameStrata call needed here.
        KE:ApplyFramePosition(f, {
            AnchorFrom = db.SelfPoint, AnchorTo = db.AnchorPoint,
            XOffset    = db.XOffset,   YOffset   = db.YOffset,
        }, { anchorFrameType = db.anchorFrameType, ParentFrame = db.ParentFrame, Strata = db.Strata })

        if db.BackdropEnabled then
            local c = db.BackdropColor or { 0, 0, 0 }
            f.bgTex:SetColorTexture(c[1], c[2], c[3], db.BackdropOpacity or 0.6)
        else
            f.bgTex:SetColorTexture(0, 0, 0, 0)
        end

        -- Straggler anchors: relative positions that only change on config change.
        -- Never re-anchored inside Render* hot paths (perf: skip-SetPoint-when-stationary).
        -- Key bracket rides LEFT of the affixes ("[12] Fortified - ...",
        -- round-3 feedback). TEXT mode anchors it here; ICON mode re-anchors
        -- it in RenderKey (icon count varies per run); with affixes hidden
        -- the stacking pass row()-anchors it alone at the right edge.
        if db.ShowAffixes and (db.AffixMode or "TEXT") == "TEXT" then
            f.keyText:ClearAllPoints()
            f.keyText:SetPoint("RIGHT", f.affixText, "LEFT", -4, 0)
        end

        f.forcesText:ClearAllPoints()
        local place = db.ForcesPlacement or "EDGE"
        if place == "CENTER" then
            f.forcesText:SetPoint("CENTER", bars.forcesBar)
        elseif place == "BESIDE" then
            f.forcesText:SetPoint("RIGHT", bars.forcesWrap, "LEFT", -4, 0)  -- overhangs backdrop left (WarpDeplete idiom)
        elseif place == "CORNER" then
            -- Fully below the bar's right corner; the stacking pass reserves
            -- a full line for it before the objectives.
            f.forcesText:SetPoint("TOPRIGHT", bars.forcesWrap, "BOTTOMRIGHT", 0, -1)
        else  -- EDGE (default): straddles the bar's BOTTOM edge at the right
              -- corner (WarpDeplete look) — half in / half out; the stacking
              -- pass reserves the protruding half-line. +2 y-bias rides the
              -- text slightly higher into the bar (2026-06-10 feedback).
            f.forcesText:SetPoint("RIGHT", bars.forcesWrap, "BOTTOMRIGHT", -2, 2)
        end
    end

    -- Length-gated vertical relayout (Fabys trick — port of timer.lua:252-258).
    -- Gate the per-element SetPoint/height accumulation on a string-length
    -- signature so MM:SS->MM:SS ticks skip relayout entirely. The signature
    -- includes objectives/deaths visibility terms so those changes still re-run.
    local run = self.run
    local objCount, objDone, objSum = 0, 0, 0
    if run and run.objectives then
        objCount = #run.objectives
        for i = 1, objCount do
            local o = run.objectives[i]
            if o.completed then objDone = objDone + 1 end
            -- quantity term is load-bearing: a count tick like "2/6" -> "3/6"
            -- keeps the same string LENGTH, so without it the length-gated
            -- relayout would never repaint a count-based objective row.
            objSum = objSum + #(o.name or "") + floor(o.clearTime or 0) + floor(o.pbTime or 0)
                            + floor(o.quantity or 0)
        end
    end
    _sigBuf[1]  = #(f.deathsText:GetText() or "")
    _sigBuf[2]  = #(f.timerText:GetText() or "") + #(f.timerSuffixText:GetText() or "")
    _sigBuf[3]  = #(f.keyText:GetText() or "")
    _sigBuf[4]  = #(f.affixText:GetText() or "")
    _sigBuf[5]  = #(f.forcesText:GetText() or "")
    _sigBuf[6]  = db.ShowThresholdLabels and 1 or 0
    _sigBuf[7]  = db.ShowForces and 1 or 0
    _sigBuf[8]  = db.ShowDeaths and 1 or 0
    _sigBuf[9]  = db.ShowObjectives and 1 or 0
    _sigBuf[10] = ((run and (run.deaths or 0) > 0) and db.ShowDeaths) and 1 or 0
    _sigBuf[11] = objCount
    _sigBuf[12] = objDone
    _sigBuf[13] = objSum
    local sig = table.concat(_sigBuf, ":")
    if f._keLayoutSig == sig then return end
    f._keLayoutSig = sig

    -- Publish the layout-cursor constants consumed by RenderObjectives (Task 3.2).
    MPT._PAD, MPT._ROW_GAP, MPT._OBJ_GAP = PAD, ROW, 2
    local y = -PAD
    local function row(fs, gap)
        if fs:IsShown() then
            fs:ClearAllPoints()
            fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
            y = y - (fs:GetStringHeight() or (db.FontSize or 13)) - (gap or ROW)
        end
    end
    row(f.deathsText)
    -- Timer row: the static total is pinned at the right edge; the "/" and
    -- the changing part chain off its LEFT with TIMER_SEP_GAP per side, so
    -- the static side never shifts while the elapsed string is re-measured
    -- each second. Single-value modes hide the sep+total pair, and the
    -- changing part anchors straight to the frame edge (no gap drift).
    if f.timerText:IsShown() then
        f.timerSuffixText:ClearAllPoints()
        f.timerSuffixText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        f.timerSepText:ClearAllPoints()
        f.timerSepText:SetPoint("TOPRIGHT", f.timerSuffixText, "TOPLEFT", -TIMER_SEP_GAP, 0)
        f.timerText:ClearAllPoints()
        if f.timerSuffixText:IsShown() then
            f.timerText:SetPoint("TOPRIGHT", f.timerSepText, "TOPLEFT", -TIMER_SEP_GAP, 0)
        else
            f.timerText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        end
        y = y - (f.timerText:GetStringHeight() or (db.FontSize or 13)) - ROW
    end
    -- Key + affix row: the affixes own the right edge with the key bracket to
    -- their LEFT (round-3 feedback). affixText is the row anchor even when
    -- hidden (ICON mode zeroes its text; icons + key hang off its rect).
    -- With affixes off entirely the key bracket row-anchors alone.
    if db.ShowAffixes then
        f.affixText:ClearAllPoints()
        f.affixText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        local rowH = max(f.affixText:GetStringHeight() or 0, f.keyText:GetStringHeight() or 0)
        if rowH == 0 then rowH = db.FontSize or 13 end
        y = y - rowH - ROW
    else
        row(f.keyText)
    end
    -- Reserve room for the threshold labels: a full row for ABOVE, the
    -- protruding half-line for EDGE (half-in/half-out on the bar's top
    -- edge); INSIDE sits fully on the bar and consumes nothing.
    if db.ShowThresholdLabels then
        local tPlace = db.ThresholdPlacement or "EDGE"
        local tSize = db.ThresholdFontSize or db.FontSize or 13
        if tPlace == "ABOVE" then
            y = y - tSize - ROW
        elseif tPlace == "EDGE" then
            y = y - floor(tSize / 2) - 2
        end
    end
    bars:ClearAllPoints()
    bars:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    bars.timerWrap:ClearAllPoints()
    bars.timerWrap:SetPoint("TOPRIGHT", bars, "TOPRIGHT", 0, 0)
    bars.forcesWrap:ClearAllPoints()
    bars.forcesWrap:SetPoint("TOPRIGHT", bars.timerWrap, "BOTTOMRIGHT", 0, -ROW)
    y = y - barH - ROW             -- timer bar
    if db.ShowForces then          -- forces bar consumes height only when shown
        y = y - barH - ROW         -- (sig term 7 re-runs this pass on toggle)
        -- Reserve room for the forces label below the bar: a full line for
        -- CORNER, the protruding half-line for EDGE (half-in/half-out).
        local fPlace = db.ForcesPlacement or "EDGE"
        local fSize = db.ForcesFontSize or db.FontSize or 13
        if fPlace == "CORNER" then
            y = y - fSize - 2
        elseif fPlace == "EDGE" then
            y = y - floor(fSize / 2) - 2
        end
    end
    -- Hand the cursor to the objectives pass: Task 3.2's RenderObjectives
    -- reads _objRowStartY/_PAD/_OBJ_GAP and writes _objRowEndY (its only
    -- return channel). Guarded until Task 3.2 defines it.
    MPT._objRowStartY = y
    MPT._objRowEndY   = nil
    if self.RenderObjectives then self:RenderObjectives() end
    f:SetHeight(-(MPT._objRowEndY or y) + PAD)
end

---------------------------------------------------------------------------------
-- Render — orchestrator (CONTRACT §54 HUD function list).
-- Called by NotifyRefresh's debounced callback (_NotifyRefreshFire). Hides the
-- HUD when there is no run or preview, else calls each Render* in order and
-- requests a deferred (length-gated) layout pass.
-- RenderObjectives (Task 3.2) is called from INSIDE ApplyLayout — it consumes
-- the layout cursor published here. Do NOT call it here: the first render
-- after a text-length change is one deferred-layout pass stale and converges
-- on the next tick (accepted behavior per spec §11).
-- Mirrors EllesmereUI RenderStandalone lines 1045-1062.
---------------------------------------------------------------------------------

function MPT:Render()
    if not self.db or not self.db.Enabled then
        if self.frames and self.frames.root then self.frames.root:Hide() end
        return
    end
    local run = self.run
    if not (run and (run.active or run.completed)) and not self.isPreview then
        if self.frames and self.frames.root then self.frames.root:Hide() end
        return
    end
    self:BuildHUD()
    self.frames.root:Show()

    self:RenderDeaths()
    self:RenderTimer()
    self:RenderKey()
    self:RenderThresholds()
    self:RenderBar()
    self:RenderForces()
    -- RenderObjectives (Task 3.2) is called from INSIDE ApplyLayout — see note above.
    self:RequestLayout()
end

---------------------------------------------------------------------------------
-- ApplySettings — single entry for GUI callbacks (Tasks 5.4+) and KE's
-- duck-typed refresh walk (Core/Main.lua:136-142, ProfileManager:419).
-- Busts the length gate, config-skip gate, and threshold geometry cache;
-- re-applies bar textures + background textures; calls ApplyLayout
-- (fonts/sizes/pos/scale/strata/backdrop); then requests a debounced
-- repaint via NotifyRefresh.
-- NOTE: ApplySettings (not BuildHUD) is the long-term owner of bar-texture
-- application; BuildHUD only seeds the initial texture at frame creation time.
---------------------------------------------------------------------------------

function MPT:ApplySettings()
    if not self.db then return end
    local f = self.frames and self.frames.root
    if not f then return end  -- nothing built yet; OnEnable/Render builds lazily
    local bars   = self.frames.bars
    local barTex = KE:GetStatusbarPath(self.db.BarTexture or "KitnUI")

    -- Re-apply the StatusBar textures (user can change BarTexture in GUI).
    bars.timerBar:SetStatusBarTexture(barTex)
    bars.forcesBar:SetStatusBarTexture(barTex)
    -- Re-apply the background textures + empty-track tint (BarBackgroundColor;
    -- BuildHUD only seeds the initial #080808 dark).
    local bgc = self.db.BarBackgroundColor or { 0.031, 0.031, 0.031 }
    bars.timerBg:SetTexture(barTex)
    bars.forcesBg:SetTexture(barTex)
    bars.timerBg:SetVertexColor(bgc[1], bgc[2], bgc[3], 0.8)
    bars.forcesBg:SetVertexColor(bgc[1], bgc[2], bgc[3], 0.8)

    -- Bust the length-gate (font/size changes restack), the threshold geometry
    -- cache (BarHeight/TickColor changes re-run _PlaceTick/_PlaceLabel), and the
    -- config-skip gate (fonts/sizes/pos/scale/backdrop re-apply).
    f._keLayoutSig    = nil
    bars._keThreshSig = nil
    f._keConfigDone   = nil  -- bust the config-skip gate

    self:ApplyLayout()    -- fonts, bar sizes, position, scale, backdrop, Strata
    self:NotifyRefresh()  -- debounced Render repaints texts/colors (works in preview)
end

---------------------------------------------------------------------------------
-- Preview fake-run (Task 2.6) — Rookery +12 demo visible when the GUI opens.
-- BuildPreviewRun() returns a FRESH table per call (never a shared static) so
-- stray mutations from render/lifecycle code cannot poison a subsequent preview.
-- Thresholds are peril-correct: affix 152 (Challenger's Peril) is in the list,
-- so ComputeThresholds reduces the base timer by 90 s before scaling ratios.
-- ShowPreview/HidePreview are idempotent — the PreviewManager may call them
-- repeatedly; the isPreview guards prevent double-show and double-hide.
---------------------------------------------------------------------------------

local function BuildPreviewRun()
    local maxTime = 1980                        -- ~33:00 limit
    local affixIDs = { 10, 152, 9 }             -- Fortified, Challenger's Peril, Tyrannical (illustrative)
    -- Resolve icon fileIDs the same way StartRun caches them (GetAffixInfo is
    -- non-secret key metadata). RenderKey's ICON mode hides any nil slot, so a
    -- retired/unknown id degrades to a missing icon, never an error.
    local affixFileIDs = {}
    for i, id in ipairs(affixIDs) do
        local _, _, fileID = C_ChallengeMode.GetAffixInfo(id)
        affixFileIDs[i] = fileID
    end
    return {
        mapID = 1387,       -- placeholder map; HUD reads cached affixNames so any id is fine for preview
        level = 12,
        affixIDs   = affixIDs,
        affixFileIDs = affixFileIDs,
        affixNames = { "Fortified", "Challenger's Peril", "Tyrannical" },
        affixNamesStr = "Fortified - Challenger's Peril - Tyrannical",
        maxTime = maxTime,
        thresholds = MPT.ComputeThresholds(maxTime, true),  -- peril-correct (affix 152 above); never hardcode
        elapsed = 600,                          -- 10:00 in
        deaths = 2, deathTimeLost = 10,
        deathLog = {
            { t = 142, name = "Healer", class = "PRIEST" },
            { t = 488, name = "Tank",   class = "WARRIOR" },
        },
        forces = { total = 240, current = 156, percent = 65.0, completed = false },
        objectives = {
            { name = "First Boss",  completed = true,  clearTime = 180,  pbTime = 165,  criteriaIndex = 1 },
            { name = "Second Boss", completed = true,  clearTime = 410,  pbTime = 430,  criteriaIndex = 2 },
            { name = "Third Boss",  completed = false, clearTime = nil,  pbTime = 700,  criteriaIndex = 3 },
            { name = "Final Boss",  completed = false, clearTime = nil,  pbTime = 1100, criteriaIndex = 4 },
            -- Count-based objective demo (Pit of Saron "Quarry Camps" pattern):
            -- totalQuantity > 1 renders the "2/6" name prefix.
            { name = "Prisoners Freed", completed = false, clearTime = nil, pbTime = nil,
              quantity = 2, totalQuantity = 6, criteriaIndex = 5 },
        },
        bestOverall = 1750,
        active = true, completed = false,
    }
end

function MPT:ShowPreview()
    if self.isPreview then return end                                          -- idempotent
    if self.run and self.run.active and not self.isPreview then return end     -- never clobber a live key
    if not (self.frames and self.frames.root) then self:BuildHUD() end
    self._savedRun = self.run                   -- stash any leftover (non-active) run state
    self.run = BuildPreviewRun()                -- fresh table per show — never a shared static
    self.isPreview = true
    self:ApplyTrackerVisibility()               -- preview always hides the Blizzard tracker
    self.frames.root:Show()
    self:Render()
end

function MPT:HidePreview()
    if not self.isPreview then return end        -- idempotent
    self.isPreview = false
    self.run = self._savedRun
    self._savedRun = nil
    -- Restore the tracker we hid for the preview. ApplyTrackerVisibility keeps
    -- it hidden when a live run still wants it (mid-key GUI close, toggle on).
    self:ApplyTrackerVisibility()
    -- Re-render for active AND completed runs (the post-run summary stays up
    -- through the fanfare; hiding it here would lose it permanently).
    if not (self.run and (self.run.active or self.run.completed)) then
        if self.frames and self.frames.root then self.frames.root:Hide() end
    else
        self:Render()
    end
end

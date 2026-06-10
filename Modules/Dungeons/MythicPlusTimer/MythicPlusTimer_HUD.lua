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

-- Reusable buffer for ApplyLayout's length-gate signature (avoids a transient
-- table allocation each time the gate is checked).
local _sigBuf = {}

---------------------------------------------------------------------------------
-- Gating helpers (module functions — not methods; take widget explicitly)
---------------------------------------------------------------------------------

-- Skip SetText when the string is identical to the prior tick (safe here:
-- all strings derive from non-secret values per spec §8).
function MPT.SetTextGated(fs, str)
    if not fs then return end
    str = str or ""
    if fs._keLast == str then return end
    fs._keLast = str
    fs:SetText(str)
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

    -- FontString factory: all text lives on root (contract §Frames rule).
    local function FS(layer)
        local fs = root:CreateFontString(nil, layer or "ARTWORK")
        fs:SetWordWrap(false)
        fs:SetNonSpaceWrap(false)
        return fs
    end

    root.deathsText    = FS()              -- "N Deaths (+penalty)"
    root.timerText     = FS()              -- "15:00 / 28:00"
    root.timerPBText   = FS()              -- gold PB beside timer (countdown)
    root.keyText       = FS()              -- "[30]" key bracket
    root.affixText     = FS()              -- affix names (TEXT mode)
    root.affixIcons    = {}                -- ICON-mode textures (lazy, Task 2.4)
    root.thresh3Text   = FS()              -- remaining label above +3 tick
    root.thresh2Text   = FS()              -- remaining label above +2 tick
    root.thresh1Text   = FS()              -- remaining label at +1 (bar end)
    root.forcesText    = FS()              -- forces percent/count text

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
    timerBg:SetVertexColor(0.12, 0.12, 0.12, 0.9)
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
    forcesBg:SetVertexColor(0.12, 0.12, 0.12, 0.9)
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

    root:Hide()
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

    local str
    if mode == "REMAINING" then
        str = remStr
    elseif mode == "REMAINING_TOTAL" then
        str = remStr .. " / " .. maxStr
    elseif mode == "ELAPSED" then
        str = elaStr
    elseif mode == "ELAPSED_DETAIL" then
        -- e.g. "21:23 (11:37 / 33:00)" — elapsed (remaining / total)
        str = elaStr .. " (" .. remStr .. " / " .. maxStr .. ")"
    else -- ELAPSED_TOTAL (default)
        str = elaStr .. " / " .. maxStr
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

local function _PlaceLabel(fs, timerBar, barW, cutoff, maxTime)
    fs:ClearAllPoints()
    local x = KE:PixelSnap(barW * (cutoff / maxTime))
    fs:SetPoint("BOTTOM", timerBar, "TOPLEFT", x, 2)
    fs:Show()
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

    -- Geometry cache: all SetPoint/SetSize/SetColorTexture calls are pure
    -- functions of this signature. Skip when nothing structural changed.
    local sig = barW .. ":" .. maxTime .. ":" .. t3 .. ":" .. t2 .. ":" .. t1 .. ":"
                .. (db.BarHeight or 14) .. ":" .. tr .. ":" .. tg .. ":" .. tb
    if bars._keThreshSig ~= sig then
        bars._keThreshSig = sig
        _PlaceTick(bars.tick3, bars.timerBar, barW, barH, tickW, t3, maxTime, tr, tg, tb)
        _PlaceTick(bars.tick2, bars.timerBar, barW, barH, tickW, t2, maxTime, tr, tg, tb)
        if db.ShowThresholdLabels then
            local f = self.frames.root
            _PlaceLabel(f.thresh3Text, bars.timerBar, barW, t3, maxTime)
            _PlaceLabel(f.thresh2Text, bars.timerBar, barW, t2, maxTime)
            _PlaceLabel(f.thresh1Text, bars.timerBar, barW, t1, maxTime)
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
    local FormatTime = MPT.FormatTime
    local elapsed = run.elapsed or 0
    self.SetTextGated(f.thresh3Text, FormatTime(MPT.ThresholdRemaining(elapsed, t3), false))
    self.SetTextGated(f.thresh2Text, FormatTime(MPT.ThresholdRemaining(elapsed, t2), false))
    self.SetTextGated(f.thresh1Text, FormatTime(MPT.ThresholdRemaining(elapsed, t1), false))
    f.thresh3Text:Show(); f.thresh2Text:Show(); f.thresh1Text:Show()
end

---------------------------------------------------------------------------------
-- RenderKey — key level bracket + affix line (TEXT or ICON mode).
-- Steps 1-3 of Task 2.4.
--
-- keyText anchor: owned by ApplyLayout (Task 2.5) — placed right-aligned at
-- the frame's right edge. affixText anchor: ApplyLayout Step 3 anchors it
-- left of keyText, growing leftward. affixIcons grow leftward from keyText.
-- This function only sets text / color / visibility.
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
        local size = db.FontSize or 13
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
                -- Grow leftward (keyText sits at the frame's right edge).
                if prev then
                    tex:SetPoint("RIGHT", prev, "LEFT", -4, 0)
                else
                    tex:SetPoint("RIGHT", f.keyText, "LEFT", -6, 0)
                end
                tex:Show()
                prev = tex
            end
        end
        -- Hide any stale icons from a previous run with more affixes.
        for i = #ids + 1, #f.affixIcons do f.affixIcons[i]:Hide() end
    elseif f.affixIcons then
        for i = 1, #f.affixIcons do f.affixIcons[i]:Hide() end
    end
end

---------------------------------------------------------------------------------
-- RenderDeaths — headline "N Deaths (+m:ss)" line.
-- Step 4 of Task 2.4. Phase-2 headline only — Task 3.5 replaces this
-- function wholesale with the full hover-log version. The boundary is
-- intentional: do not add tooltip or log logic here.
--
-- Blank at 0 deaths (spec §7.1). Format is "N Deaths (+m:ss)" — penalty
-- ADDS to elapsed time (deliberate deviation from EUI's leading "-" sign).
-- Color: db.DeathsColor when set, fallback red (0.93, 0.33, 0.33).
-- SetTextGated: safe — deathTimeLost is plain math (spec §8 "GetDeathCount").
---------------------------------------------------------------------------------

function MPT:RenderDeaths()
    local run, db = self.run, self.db
    local f = self.frames and self.frames.root
    if not f or not db then return end
    if not db.ShowDeaths or (run.deaths or 0) <= 0 then
        f.deathsText:Hide()
        return
    end
    local n = run.deaths
    local str = format("%d Death%s (+%s)", n, n ~= 1 and "s" or "",
        MPT.FormatTime(run.deathTimeLost or 0, false))
    self.SetTextGated(f.deathsText, str)
    if db.DeathsColor then
        self.SetColorGated(f.deathsText, db.DeathsColor[1], db.DeathsColor[2], db.DeathsColor[3])
    else
        self.SetColorGated(f.deathsText, 0.93, 0.33, 0.33)
    end
    f.deathsText:Show()
end

---------------------------------------------------------------------------------
-- RenderForces — forces StatusBar fill + percent/count/custom text.
-- Step 5 of Task 2.4.
--
-- run.forces = { total, current, percent, completed } (plain math — no
-- issecretvalue guard per spec §8 "aggregate GetCriteriaInfo").
-- Fill = percent/100 via SetValueGated.
--
-- Color resolution order (highest wins last):
--   1. db.ForcesColor (base)
--   2. db.ForcesBandedColors (quintile palette; skipped at completion)
--   3. db.ForcesCompleteColor (wins unconditionally at completion)
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
    self.SetTextGated(f.forcesText, str)
    self.SetColorGated(f.forcesText, r, g, b)
    f.forcesText:Show()
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
        bars:SetWidth(barW)

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
        f.affixText:ClearAllPoints()
        f.affixText:SetPoint("RIGHT", f.keyText, "LEFT", -6, 0)  -- grows leftward from keyText

        f.forcesText:ClearAllPoints()
        local place = db.ForcesPlacement or "CORNER"
        if place == "CENTER" then
            f.forcesText:SetPoint("CENTER", bars.forcesBar)
        elseif place == "BESIDE" then
            f.forcesText:SetPoint("RIGHT", bars.forcesWrap, "LEFT", -4, 0)  -- overhangs backdrop left (WarpDeplete idiom)
        else  -- CORNER (default)
            f.forcesText:SetPoint("BOTTOMRIGHT", bars.forcesWrap, "TOPRIGHT", 0, 1)
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
            objSum = objSum + #(o.name or "") + floor(o.clearTime or 0) + floor(o.pbTime or 0)
        end
    end
    _sigBuf[1]  = #(f.deathsText:GetText() or "")
    _sigBuf[2]  = #(f.timerText:GetText() or "")
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

    local ROW = 6
    -- Publish the layout-cursor constants consumed by RenderObjectives (Task 3.2).
    MPT._PAD, MPT._ROW_GAP, MPT._OBJ_GAP = PAD, ROW, 4
    local y = -PAD
    local function row(fs, gap)
        if fs:IsShown() then
            fs:ClearAllPoints()
            fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
            y = y - (fs:GetStringHeight() or (db.FontSize or 13)) - (gap or ROW)
        end
    end
    row(f.deathsText)
    row(f.timerText)
    row(f.keyText)  -- affixText anchored left of keyText in Step 2; ICON-mode icons anchored in RenderKey (grow leftward)
    if db.ShowThresholdLabels then
        y = y - (db.ThresholdFontSize or db.FontSize or 13) - ROW
    end
    bars:ClearAllPoints()
    bars:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    bars.timerWrap:ClearAllPoints()
    bars.timerWrap:SetPoint("TOPRIGHT", bars, "TOPRIGHT", 0, 0)
    bars.forcesWrap:ClearAllPoints()
    bars.forcesWrap:SetPoint("TOPRIGHT", bars.timerWrap, "BOTTOMRIGHT", 0, -ROW)
    y = y - (barH * 2) - ROW * 2
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
    -- Re-apply the background textures (same texture; vertex-colored dark in BuildHUD).
    bars.timerBg:SetTexture(barTex)
    bars.forcesBg:SetTexture(barTex)

    -- Bust the length-gate (font/size changes restack), the threshold geometry
    -- cache (BarHeight/TickColor changes re-run _PlaceTick/_PlaceLabel), and the
    -- config-skip gate (fonts/sizes/pos/scale/backdrop re-apply).
    f._keLayoutSig    = nil
    bars._keThreshSig = nil
    f._keConfigDone   = nil  -- bust the config-skip gate

    self:ApplyLayout()    -- fonts, bar sizes, position, scale, backdrop, Strata
    self:NotifyRefresh()  -- debounced Render repaints texts/colors (works in preview)
end

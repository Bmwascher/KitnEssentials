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
local floor = math.floor   -- luacheck: ignore 211 -- used by Tasks 2.4+
local min, max, abs = math.min, math.max, math.abs  -- max/abs used here; min used by RenderBar
local format = string.format  -- luacheck: ignore 211 -- used by Tasks 2.4+

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
    bars.timerWrap, bars.timerBar = timerWrap, timerBar

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
    bars.forcesWrap, bars.forcesBar = forcesWrap, forcesBar

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
    if maxTime <= 0 then return end

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
    bar:SetStatusBarColor(r, g, b)
end

---------------------------------------------------------------------------------
-- RenderThresholds — pixel-snapped tick marks at +3/+2 cutoffs, and
-- remaining-time labels ABOVE the bar at +3/+2/+1 (WarpDeplete look).
-- Ticks: 2 physical pixels wide, db.TickColor, parented to timerBar.
-- Labels: gated on db.ShowThresholdLabels; use MPT.ThresholdRemaining.
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

    local function placeTick(tex, cutoff)
        tex:ClearAllPoints()
        tex:SetSize(tickW, barH)
        local x = KE:PixelSnap(barW * (cutoff / maxTime)) - tickW / 2
        tex:SetPoint("TOPLEFT", bars.timerBar, "TOPLEFT", x, 0)
        tex:SetColorTexture(tr, tg, tb, 1)
        tex:Show()
    end
    placeTick(bars.tick3, run.thresholds.plus3)
    placeTick(bars.tick2, run.thresholds.plus2)

    -- Remaining-time labels above the bar (WarpDeplete look)
    local f = self.frames.root
    if not db.ShowThresholdLabels then
        self.SetTextGated(f.thresh3Text, ""); f.thresh3Text:Hide()
        self.SetTextGated(f.thresh2Text, ""); f.thresh2Text:Hide()
        self.SetTextGated(f.thresh1Text, ""); f.thresh1Text:Hide()
        return
    end
    local FormatTime = MPT.FormatTime
    local elapsed = run.elapsed or 0
    local function placeLabel(fs, cutoff)
        local remain = MPT.ThresholdRemaining(elapsed, cutoff)
        self.SetTextGated(fs, FormatTime(remain, false))
        fs:ClearAllPoints()
        local x = KE:PixelSnap(barW * (cutoff / maxTime))
        fs:SetPoint("BOTTOM", bars.timerBar, "TOPLEFT", x, 2)
        fs:Show()
    end
    placeLabel(f.thresh3Text, run.thresholds.plus3)
    placeLabel(f.thresh2Text, run.thresholds.plus2)
    placeLabel(f.thresh1Text, run.thresholds.plus1)  -- plus1 == maxTime (bar end)
end

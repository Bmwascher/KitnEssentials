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
local floor = math.floor   -- luacheck: ignore 211 -- used by Tasks 2.2+
local min, max, abs = math.min, math.max, math.abs  -- luacheck: ignore 211 -- used by Tasks 2.2+/SetValueGated
local format = string.format  -- luacheck: ignore 211 -- used by Tasks 2.2+

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

-- Skip SetValue when the new fill differs from the last by < 1 physical
-- pixel of the bar's pixel width. widthPx = bar width in addon coords.
function MPT.SetValueGated(bar, v, widthPx)
    if not bar then return end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    local last = bar._keLastValue
    if last and widthPx and abs(v - last) * widthPx < 1 then return end
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

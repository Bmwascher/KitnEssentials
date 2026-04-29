-- ╔══════════════════════════════════════════════════════════╗
-- ║  EbonMightTracker.lua                                    ║
-- ║  Module: Ebon Might Tracker                              ║
-- ║  Purpose: Displays Ebon Might buff duration with crit    ║
-- ║           and duped cast detection for Augmentation.     ║
-- ║  Note: Evoker only (Augmentation).                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class EbonMightTracker: AceModule, AceEvent-3.0
local EMT = KitnEssentials:NewModule("EbonMightTracker", "AceEvent-3.0")
EMT.classRestriction = "EVOKER"

local LCG = LibStub("LibCustomGlow-1.0", true)

local C_UnitAuras     = C_UnitAuras
local C_Spell         = C_Spell
local C_Timer         = C_Timer
local C_SpellBook     = C_SpellBook
local CreateFrame     = CreateFrame
local UnitClass       = UnitClass
local UnitExists      = UnitExists
local UnitStat        = UnitStat
local GetTime         = GetTime
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local GetNumGroupMembers    = GetNumGroupMembers
local IsInGroup             = IsInGroup
local IsInRaid              = IsInRaid
local InCombatLockdown      = InCombatLockdown
local issecretvalue   = issecretvalue
local pcall           = pcall
local pairs           = pairs
local ipairs          = ipairs
local wipe            = wipe
local math_floor      = math.floor
local math_max        = math.max

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local EBON_MIGHT_SELF    = 395296     -- Aura on self
local EBON_MIGHT_OTHERS  = 395152     -- Aura on allies
local CHRONO_CRIT_TALENT = 431874     -- Chronowarden "canCrit" talent (Double Time)
local DUPE_TALENT        = 1259175    -- "canDupe" talent (apex dupe proc)
local AUG_SPEC_ID        = 1473       -- Augmentation spec ID

-- Cast multiplier ratio threshold. History entries are normalized by dividing
-- out the dupe factor at observation time (norm / 1.75 if totem was on),
-- collapsing all entries into "as-if-no-dupe" space. The classifier then
-- only needs to tell base (1.0×) from crit (1.5×) — single threshold at the
-- midpoint, 1.25.
local MULT_CRIT  = 1.25
-- Dupe boost factor — divided out at observation to normalize history entries.
local DUPE_FACTOR = 1.75

-- Cast history sliding window for relative classification.
--   MAX_HISTORY_AGE — entries older than this decay out. Short enough that
--     mid-fight stat changes (trinket proc up/down) recalibrate quickly.
--   MAX_HISTORY_SIZE — hard upper bound on entries kept.
local MAX_HISTORY_AGE  = 30
local MAX_HISTORY_SIZE = 20

-- Pandemic glow shown when aura has <=4s remaining. Overlays the icon without
-- replacing the crit/dupe border. Color + type configurable via DB (pixel /
-- autocast / button / proc — see LibCustomGlow).
local PANDEMIC_WINDOW            = 4
local PANDEMIC_GLOW_COLOR_FALLBACK = { 1, 1, 0, 1 }  -- used when db is unset

local ICON_ID          = 5061347     -- Ebon Might spell icon
local REFRESH_INTERVAL = 0.5         -- Countdown update rate (seconds)

-- Debug flag. Gate every log with `if DEBUG_EMT then ... end`. Leave in place
-- after diagnosing so the next regression gets free instrumentation.
-- Flip to true to see per-cast classification (crit + totem) and seed refresh.
local DEBUG_EMT = false

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
EMT.frame               = nil
EMT.iconFrame           = nil
EMT.iconTexture         = nil
EMT.countdownText       = nil
EMT.stateLabel          = nil
EMT.ticker              = nil
EMT.isAugSpec           = false
EMT.canCrit             = false
EMT.canDupe             = false
EMT.isPreview           = false
EMT.inGroup             = false
EMT._shown              = false
EMT.editModeRegistered  = false

-- Cast-to-cast relative classification state.
--
-- Why this approach: in WoW 12.0 encounters, UnitStat returns secret values
-- for ALL addons regardless of execution context (confirmed via a zero-lib
-- sibling addon still hitting the same wall). Absolute mainstat-based
-- classification therefore requires a stale saved snapshot which misclassifies
-- whenever stats shift mid-fight (trinket procs, gear swaps).
--
-- Relative classification sidesteps the problem: we don't need the absolute
-- mainstat. Every EM cast produces observable aura values on allies
-- (aura.points is AllowedWhenTainted). The MINIMUM observed value within the
-- rolling window is the "base per ally" — crits are strictly larger. Current
-- cast value divided by that minimum gives the cast multiplier (1.0 = base,
-- 1.5 = crit), which maps to a single classification threshold (1.25).
--
-- Dupe is NOT determined by ratio. Instead, history entries are normalized
-- by dividing out the dupe factor (1.75x) when the duplicate totem was
-- active at the moment of observation. That collapses every history entry
-- into pure base/crit space, so the ratio comparison only has to handle
-- one binary decision. `isDuped` itself is set live in UpdateDisplay from
-- the totem state, independently of any history math.
--
-- Caveats:
--   - First cast with empty history compares against the seed (saved
--     mainstat × 0.16) if available, else defaults to "base".
--   - 30s window: stat shifts mid-fight recalibrate as new casts age out
--     pre-shift entries.
--
-- Entries shape: { time, norm, exp } where:
--   - norm = (targetMS × max(2, count)) / (totemAtObservation ? 1.75 : 1.0)
--   - exp  = selfExpirationTime — identifies which cast the entry belongs to
--     (distinguishes new casts from additional ally auras for the same cast).
EMT._castHistory             = {}
EMT._lastRecordedExpiration  = 0
-- `_castNeedsPush` is set true by the UNIT_AURA handler ONLY when an EM
-- ally-aura `addedAuras` event fires (i.e. a new cast just landed on an
-- ally, so targetMainStat reflects the cast's roll outcome). CalcCrit checks
-- this flag to gate history writes + classification updates. Mid-buff
-- updatedAuraInstanceIDs events (live mainstat tracking) DON'T set this
-- flag, so classification stays locked to the cast-time outcome.
EMT._castNeedsPush           = false

-- Seed norm = bootstrap baseline derived from db.MainStat, used ONLY when
-- history is empty (first cast of a session). Without a seed, the first
-- cast is its own min → always classified as base. Computed as MainStat ×
-- 0.16, which equals the normalized value of a base-multiplier cast at the
-- saved mainstat. Once any real cast lands, that real cast's norm becomes
-- the min and the seed is ignored — keeping it bootstrap-only avoids the
-- stale-seed-inflates-ratios trap when saved stat is below current. Auto-
-- refreshed on combat exit (PLAYER_REGEN_ENABLED) + manual GUI button.
EMT._seedNorm                = nil

-- Tracked aura state
EMT.selfAuraInstanceID  = 0
EMT.selfExpirationTime  = 0
-- ebonMight: flat list of { auraId, value, target } — mirrors v1.2.0's structure
-- (preserved because CalcCrit iterates values linearly and dedupes on auraId).
EMT.ebonMight           = {}

-- Calc outputs
EMT.calc = {
    calcMainStat   = 0,
    targetMainStat = 0,
    targetcount    = 0,
}

-- Display flags (fed to the UI color picker).
--   isCrit  — locked per cast; set by CalcCrit from the relative ratio.
--   isDuped — LIVE; set every UpdateDisplay tick from IsDuplicateActive(),
--             flips with the duplicate totem spawning/expiring during a buff.
EMT.isCrit  = false
EMT.isDuped = false

-- Border tracking for pandemic highlighting (avoids re-applying the same style)
EMT._pandemicActive = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function EMT:UpdateDB()
    self.db = KE.db.profile.EbonMightTracker
end

---------------------------------------------------------------------------------
-- Spec / Talent Detection
---------------------------------------------------------------------------------
function EMT:IsValidSpec()
    local _, classToken = UnitClass("player")
    if classToken ~= "EVOKER" then return false end
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    local specID = GetSpecializationInfo(specIndex)
    return specID == AUG_SPEC_ID
end

function EMT:UpdateCanCrit()
    local ok, known = pcall(C_SpellBook.IsSpellKnown, CHRONO_CRIT_TALENT)
    self.canCrit = ok and known == true
end

function EMT:UpdateCanDupe()
    local ok, known = pcall(C_SpellBook.IsSpellKnown, DUPE_TALENT)
    self.canDupe = ok and known == true
end

function EMT:UpdateTalents()
    self:UpdateCanCrit()
    self:UpdateCanDupe()
end

---------------------------------------------------------------------------------
-- Aura Value Extraction
---------------------------------------------------------------------------------
-- Pick the largest positive point value from aura.points. Replaces the
-- hardcoded points[2] read — Blizzard has reshuffled the points table in
-- the past and may again. Largest positive is always the mainstat delta.
function EMT:BestPoint(aura)
    if not aura or not aura.points then return nil end
    if issecretvalue(aura.points) then return nil end
    local best
    for _, v in pairs(aura.points) do
        if type(v) == "number" and v > 0 and (not best or v > best) then
            best = v
        end
    end
    return best
end

---------------------------------------------------------------------------------
-- Data Management
---------------------------------------------------------------------------------
function EMT:ClearData()
    self.selfAuraInstanceID = 0
    self.selfExpirationTime = 0
    wipe(self.ebonMight)
    self.calc.calcMainStat   = 0
    self.calc.targetMainStat = 0
    self.calc.targetcount    = 0
    self.isCrit  = false
    self.isDuped = false
    -- Note: _castHistory is intentionally NOT wiped here. History persists
    -- across aura full-refreshes (isFullUpdate) and EM drop/reapply cycles so
    -- we don't lose calibration. It IS wiped on OnDisable / group change.
end

---------------------------------------------------------------------------------
-- Aura Scanning (full refresh on isFullUpdate)
---------------------------------------------------------------------------------
function EMT:ScanAuras()
    self:ClearData()
    if not self.isAugSpec then return end

    -- Read self aura by spell name
    local selfName = C_Spell.GetSpellName(EBON_MIGHT_SELF)
    if selfName then
        local auraData = C_UnitAuras.GetAuraDataBySpellName("player", selfName, "HELPFUL|PLAYER")
        if auraData and auraData.auraInstanceID then
            if not issecretvalue(auraData.applications) then
                self.selfAuraInstanceID = auraData.auraInstanceID
                if auraData.expirationTime and not issecretvalue(auraData.expirationTime) then
                    self.selfExpirationTime = auraData.expirationTime
                end
            end
        end
    end

    -- Read ally auras by iterating roster
    if self.inGroup then
        local othersName = C_Spell.GetSpellName(EBON_MIGHT_OTHERS)
        if othersName then
            local size = GetNumGroupMembers()
            local token = IsInRaid() and "raid" or "party"
            for i = 1, size do
                local unit = token .. i
                if UnitExists(unit) then
                    local auraData = C_UnitAuras.GetAuraDataBySpellName(unit, othersName, "HELPFUL|PLAYER")
                    if auraData and auraData.auraInstanceID and not issecretvalue(auraData.applications) then
                        local value = self:BestPoint(auraData) or 0
                        table.insert(self.ebonMight, {
                            auraId = auraData.auraInstanceID,
                            value  = value,
                            target = unit,
                        })
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Cast History (sliding window for relative classification)
---------------------------------------------------------------------------------
-- All entries store NORMALIZED norm (count-corrected AND dupe-divided-out)
-- so they're directly comparable in pure base/crit space regardless of how
-- many allies a cast hit or whether the duplicate totem was active when the
-- cast landed. Caller computes the effective norm and passes it in.
--
-- Push happens ONCE per cast, triggered by the `_castNeedsPush` flag set on
-- an ally `addedAuras` event. We deliberately DO NOT update on later mid-
-- buff `updatedAuraInstanceIDs` events: those reflect live mainstat shifts
-- after the cast, which would contaminate the cast's roll outcome.
function EMT:PushCastHistory(effectiveNorm, now, exp)
    if not effectiveNorm or effectiveNorm <= 0 then return end
    table.insert(self._castHistory, { time = now, norm = effectiveNorm, exp = exp })
    if #self._castHistory > MAX_HISTORY_SIZE then
        table.remove(self._castHistory, 1)
    end
end

-- RefreshCurrentCastNorm: refresh the latest entry when another ally's aura
-- arrives in a later UNIT_AURA event for the same cast (staggered raid
-- application). The per-ally value is identical for all allies in one cast,
-- so only the observed count grows — and the effective norm with it.
function EMT:RefreshCurrentCastNorm(effectiveNorm, now, exp)
    if not effectiveNorm or effectiveNorm <= 0 then return end
    if #self._castHistory == 0 then return end
    local last = self._castHistory[#self._castHistory]
    if last.exp ~= exp then return end
    last.norm = effectiveNorm
    last.time = now
end

-- PruneCastHistory + minimum extraction in one pass. Returns (minNorm, fromSeed).
-- Real-cast min wins if any exists; seed is used only as a bootstrap when
-- history is empty (first cast of a session). Keeping seed as bootstrap-only
-- (rather than a floor on min) prevents the stale-seed-inflates-ratios trap
-- when the saved mainstat is lower than the current in-combat stat.
function EMT:GetHistoryMin(now)
    local cutoff = now - MAX_HISTORY_AGE
    local writeIdx = 1
    local realMin
    for readIdx = 1, #self._castHistory do
        local entry = self._castHistory[readIdx]
        if entry.time >= cutoff then
            self._castHistory[writeIdx] = entry
            writeIdx = writeIdx + 1
            if not realMin or entry.norm < realMin then
                realMin = entry.norm
            end
        end
    end
    -- Clear trailing entries we kept above writeIdx.
    for i = #self._castHistory, writeIdx, -1 do
        self._castHistory[i] = nil
    end

    if realMin then return realMin, false end
    if self._seedNorm then return self._seedNorm, true end
    return nil, false
end

-- RefreshSeed: recompute the seed floor from the saved mainstat. Seed norm
-- equals mainstat × 0.16, which is the normalized value of a base-multiplier
-- cast (count-independent because targetMS × max(2, count) cancels the
-- division by max(2, count) in basePerAlly).
function EMT:RefreshSeed()
    if self.db and self.db.MainStat and self.db.MainStat > 0 then
        self._seedNorm = self.db.MainStat * 0.16
    else
        self._seedNorm = nil
    end
end

---------------------------------------------------------------------------------
-- Duplicate Entity Poll (authoritative dupe signal)
---------------------------------------------------------------------------------
-- Augmentation's "Duplicate" apex-talent (spellID 1259175) summons a future
-- version of the player. Talent text: "While your duplicate is active, your
-- Ebon Might grants 75% additional stats." The boost applies dynamically
-- based on the duplicate's CURRENT state — EM aura values change as the
-- duplicate spawns/despawns mid-buff.
--
-- TotemFrame.totemPool tracks the player's totem/summon frames. Polling
-- GetNumActive() is read-only and safe. This poll is the AUTHORITATIVE dupe
-- signal: it drives the live `isDuped` display flag in UpdateDisplay AND is
-- read at cast-observation time in CalcCrit to normalize history entries
-- (divide out the 1.75x dupe boost so all entries sit in pure base/crit
-- space).
function EMT:IsDuplicateActive()
    if not self.canDupe then return false end
    if not TotemFrame or not TotemFrame.totemPool or not TotemFrame.totemPool.GetNumActive then
        return false
    end
    local ok, n = pcall(TotemFrame.totemPool.GetNumActive, TotemFrame.totemPool)
    if not ok or type(n) ~= "number" then return false end
    return n > 0
end

---------------------------------------------------------------------------------
-- Crit Classification (relative, history-based, locked per cast)
---------------------------------------------------------------------------------
-- CalcCrit: gated by `_castNeedsPush`. Runs ONLY when an ally's EM aura was
-- freshly added via `addedAuras` — meaning the current cast just landed and
-- targetMainStat reflects the cast's roll value.
--
-- Sets `isCrit` only. `isDuped` is handled live in UpdateDisplay from the
-- totem signal — it can flip mid-buff as the duplicate spawns/expires.
--
-- Mid-buff stat tracking (updatedAuraInstanceIDs) is IGNORED here so the
-- crit classification locks to the cast-time outcome. Ticker refreshes also
-- early-exit and reuse the stored isCrit.
--
-- Flow when the flag is set:
--   1. Collapse current self.ebonMight into max ally value + ally count.
--   2. Read totem-at-observation. Compute effectiveNorm = (targetMS ×
--      max(2, count)) / (totem ? 1.75 : 1.0) — collapses the entry into
--      pure base/crit space regardless of dupe state.
--   3. Get prior history's min (and a seed bootstrap if history is empty).
--   4. ratio = effectiveNorm / minNorm; isCrit = ratio >= 1.25.
--   5. Push/refresh history with effectiveNorm AFTER classification, so the
--      current cast feeds the next cast's calibration but never its own.
--
-- Caveats:
--   - First cast with empty history AND no seed: defaults to "base". The
--     seed (saved mainstat × 0.16) covers the common case.
--   - If every cast in the 30s window happens to be a crit, min is inflated
--     and subsequent crits look like base. Statistically rare over a full
--     fight; the next base cast recalibrates within seconds.
--   - Mainstat shifts mid-fight: all entries in the window pre-shift become
--     stale relative to current. Within ~30s the window recycles to current-
--     stat-regime entries.
function EMT:CalcCrit()
    -- Mid-buff stat updates and ticker refreshes skip the whole pipeline —
    -- the cast's classification is already locked. Display stays stable.
    if not self._castNeedsPush then return end
    self._castNeedsPush = false

    self.calc.targetcount    = 0
    self.calc.targetMainStat = 0

    local addedIds = {}
    for _, aura in pairs(self.ebonMight) do
        local dup = false
        for _, id in pairs(addedIds) do
            if aura.auraId == id then dup = true; break end
        end
        if not dup then
            if self.calc.targetMainStat < aura.value then
                self.calc.targetMainStat = aura.value
            end
            self.calc.targetcount = self.calc.targetcount + 1
            table.insert(addedIds, aura.auraId)
        end
    end

    if self.calc.targetcount == 0 or self.calc.targetMainStat <= 0 then
        self.calc.calcMainStat = 0
        self.isCrit  = false
        return
    end

    local now = GetTime()
    local exp = self.selfExpirationTime

    -- Normalize observed value to "as-if-no-dupe" space by dividing out the
    -- 1.75x dupe boost when the totem is currently active. The EM aura value
    -- updates dynamically with totem state, so totem-at-observation tells us
    -- whether the read includes the dupe boost. Both history entries and
    -- currentNorm sit in the same crit-only space after this normalization,
    -- so the classifier just needs base-vs-crit (single threshold at 1.25).
    local totemAtObs = self:IsDuplicateActive()
    local rawNorm = self.calc.targetMainStat * math_max(2, self.calc.targetcount)
    local effectiveNorm = totemAtObs and (rawNorm / DUPE_FACTOR) or rawNorm

    -- Classify FIRST against prior history only (current cast not yet pushed)
    -- so cast 1 of a session compares against seed/empty rather than itself.
    local minNorm, fromSeed = self:GetHistoryMin(now)
    local ratio
    local isCrit
    if not minNorm or minNorm <= 0 then
        -- No baseline. Default to non-crit; isDuped is filled in live by
        -- UpdateDisplay.
        ratio  = 1.0
        isCrit = false
    else
        ratio  = effectiveNorm / minNorm
        isCrit = ratio >= MULT_CRIT
    end

    -- Talent gate.
    if not self.canCrit then isCrit = false end
    self.isCrit = isCrit

    -- Push/refresh history AFTER classification so the current cast feeds
    -- the NEXT cast's calibration but never its own.
    if exp > self._lastRecordedExpiration then
        self._lastRecordedExpiration = exp
        self:PushCastHistory(effectiveNorm, now, exp)
    else
        self:RefreshCurrentCastNorm(effectiveNorm, now, exp)
    end

    self.calc.calcMainStat = minNorm or 0   -- debug/inspection surface

    if DEBUG_EMT then
        local n = #self._castHistory
        local seedTag = fromSeed and " (seed)" or ""
        KE:Print(("[EMT] tc=%d targetMS=%d effNorm=%d minNorm=%d%s n=%d ratio=%.2f totem=%s -> crit=%s")
            :format(self.calc.targetcount, self.calc.targetMainStat,
                    math_floor(effectiveNorm + 0.5), math_floor((minNorm or 0) + 0.5),
                    seedTag, n, ratio, tostring(totemAtObs), tostring(self.isCrit)))
    end
end

---------------------------------------------------------------------------------
-- Main Stat Update (GUI button — feeds the first-cast seed)
---------------------------------------------------------------------------------
-- Saves UnitStat → db.MainStat → seed (via RefreshSeed). The seed is used
-- ONLY for the very first cast of a session (when the rolling window has
-- nothing to compare against); thereafter real casts take over the min and
-- the saved value becomes inert. AutoRefreshSeed updates this automatically
-- on combat exit, so the button is mostly a manual fallback.
function EMT:UpdateMainStat()
    if InCombatLockdown() then
        KE:Print("|cffff3333Ebon Might Tracker:|r Can't save while in combat.")
        return false
    end
    local stat = UnitStat("player", 4)
    if issecretvalue(stat) then
        KE:Print("|cffff3333Ebon Might Tracker:|r Primary stat is currently secret — step out of combat/encounter and try again.")
        return false
    end
    stat = math_floor(stat + 0.5)
    self.db.MainStat = stat
    self:RefreshSeed()
    KE:Print(("|cff33ff33Ebon Might Tracker:|r Saved primary stat: %d (used as the first-cast baseline; later casts auto-calibrate)."):format(stat))
    self:UpdateDisplay()
    return true
end

-- Auto-refresh seed on combat exit. Out-of-combat UnitStat reads are
-- usually non-secret even from our (tainted) execution context, so we can
-- update the saved baseline without the user having to press the button.
function EMT:AutoRefreshSeed()
    if not self.isAugSpec then return end
    if InCombatLockdown() then return end
    local stat = UnitStat("player", 4)
    if issecretvalue(stat) or stat <= 0 then return end
    stat = math_floor(stat + 0.5)
    if self.db.MainStat == stat then return end
    self.db.MainStat = stat
    self:RefreshSeed()
    if DEBUG_EMT then
        KE:Print(("[EMT] seed auto-refreshed: %d"):format(stat))
    end
end

---------------------------------------------------------------------------------
-- Pandemic Glow (LibCustomGlow dispatch)
---------------------------------------------------------------------------------
-- Dispatches across LCG's four glow styles. All types are stopped on Stop so
-- a user-initiated type-change mid-active-window cleans up the old overlay
-- before Start applies the new one. Defaults + tuning mirror TimeSpiral.
function EMT:StartPandemicGlow()
    if not LCG or not self.frame then return end
    local color = self.db.PandemicColor or PANDEMIC_GLOW_COLOR_FALLBACK
    local glowType = self.db.PandemicGlowType or "pixel"

    if glowType == "pixel" then
        LCG.PixelGlow_Start(self.frame, color, 8, 0.25, 8, 2, 1, 1, false, nil)
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Start(self.frame, color, 8, 0.25, 1, 1, 1, nil)
    elseif glowType == "button" then
        LCG.ButtonGlow_Start(self.frame, color, 0)
    elseif glowType == "proc" then
        LCG.ProcGlow_Start(self.frame, {
            color = color,
            startAnim = false,
            duration = 1,
        })
    end
end

function EMT:StopPandemicGlow()
    if not LCG or not self.frame then return end
    -- Stop all four types defensively — covers the case where the user swapped
    -- glow type while the old one was still running.
    LCG.PixelGlow_Stop(self.frame)
    LCG.AutoCastGlow_Stop(self.frame)
    LCG.ButtonGlow_Stop(self.frame)
    LCG.ProcGlow_Stop(self.frame)
end

-- Restart the glow with current DB settings if pandemic is currently active.
-- Called from ApplySettings so that glow-type or color changes made in the
-- GUI take effect immediately without waiting for the next edge transition.
function EMT:RefreshPandemicGlow()
    if self._pandemicActive then
        self:StopPandemicGlow()
        self:StartPandemicGlow()
    end
end

---------------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------------
-- Base state uses fully transparent borders so the icon sits flush with no
-- visible frame. Crit/dupe states override color + size to "light up".
local DEFAULT_BORDER_COLOR = { 0, 0, 0, 0 }
local BASE_BORDER_SIZE = 1
local DUPE_BORDER_SIZE = 2
local CRIT_BORDER_SIZE = 2

-- Show/hide a FontString together with its KE soft outline shadows. Calling
-- Hide() on the main FontString alone leaves the 8 shadow FontStrings visible
-- (separate objects on fontString._keSoftOutline), which appears as a ghost
-- of the hidden text.
local function SetTextElementShown(fontString, shown)
    if not fontString then return end
    if shown then
        fontString:Show()
        if fontString._keSoftOutline then
            fontString._keSoftOutline:SetShown(true)
        end
    else
        fontString:Hide()
        if fontString._keSoftOutline then
            fontString._keSoftOutline:SetShown(false)
        end
    end
end

-- Recolor and resize the four border strips created by KE:AddIconBorders.
-- `size` is screen-pixel intent (1 = base, 2 = crit/dupe); multiply by
-- KE:GetPixelSize() so the highlight renders crisply at any UI scale.
function EMT:SetBorderStyle(color, size)
    if not self.iconFrame or not self.iconFrame.borders then return end
    local r, g, b, a = KE:ResolveColor(color, { 0, 0, 0, 1 })
    local borders = self.iconFrame.borders
    local px = size * KE:GetPixelSize()
    for _, tex in pairs(borders) do
        if tex.SetColorTexture then
            tex:SetColorTexture(r, g, b, a)
        end
    end
    if borders.top    and borders.top.SetHeight    then borders.top:SetHeight(px)    end
    if borders.bottom and borders.bottom.SetHeight then borders.bottom:SetHeight(px) end
    if borders.left   and borders.left.SetWidth    then borders.left:SetWidth(px)    end
    if borders.right  and borders.right.SetWidth   then borders.right:SetWidth(px)   end
end

function EMT:UpdateDisplay()
    if not self.countdownText then return end

    -- Update countdown text
    local remaining = 0
    if self.selfAuraInstanceID == 0 then
        self.countdownText:SetText("0")
    else
        remaining = self.selfExpirationTime - GetTime()
        if remaining < 0 then remaining = 0 end
        self.countdownText:SetText(tostring(math_floor(remaining)))
    end

    -- Classify current cast. CalcCrit early-exits unless _castNeedsPush is
    -- set (cast just landed on an ally) — so isCrit is locked per cast and
    -- mid-buff stat updates don't flip it. Out of group = no allies = nothing
    -- to classify against.
    if self.inGroup then
        self:CalcCrit()
    else
        self.isCrit = false
    end

    -- isDuped is LIVE: equals the duplicate totem's current state. Updates
    -- every UpdateDisplay tick (0.5s ticker) and on PLAYER_TOTEM_UPDATE for
    -- instant feedback. The talent boosts EM aura value dynamically while
    -- the duplicate is alive, so the display reflects current reality
    -- regardless of whether the duplicate spawned before or after the cast.
    self.isDuped = self.inGroup and self:IsDuplicateActive() or false

    -- Preview override: forces a CRIT look regardless of detection so the user
    -- can see the highlight style in the GUI preview.
    if self.isPreview then
        self.isCrit  = true
        self.isDuped = false
    end

    -- Pick text + border color + border size + state-label text.
    -- OnlyShowCrit suppresses the DUPE branch: when the user has opted into
    -- "crits only", the orange DUPE overlay isn't a crit and shouldn't paint
    -- on top of pandemic-forced visibility. Crits still surface normally.
    local effectiveDuped = self.isDuped and not self.db.OnlyShowCrit
    local tr, tg, tb, ta, borderColor, borderSize, labelText
    if self.isCrit then
        tr, tg, tb, ta = KE:ResolveColor(self.db.CritColor, { 1, 0, 1, 1 })
        borderColor = self.db.CritColor or { 1, 0, 1, 1 }
        borderSize = CRIT_BORDER_SIZE
        labelText = "CRIT"
    elseif effectiveDuped then
        tr, tg, tb, ta = KE:ResolveColor(self.db.DupeColor, { 1, 0.5, 0, 1 })
        borderColor = self.db.DupeColor or { 1, 0.5, 0, 1 }
        borderSize = DUPE_BORDER_SIZE
        labelText = "DUPE"
    else
        tr, tg, tb, ta = KE:ResolveColor(self.db.BaseColor, { 1, 1, 1, 1 })
        borderColor = DEFAULT_BORDER_COLOR
        borderSize = BASE_BORDER_SIZE
        labelText = ""
    end

    -- Pandemic pixel glow (only when enabled + aura is running + <=4s left).
    -- Separate from the crit/dupe border colors so the refresh cue stacks on
    -- top of whatever color the underlying cast was (crit purple, dupe orange,
    -- or base). Edge-triggered: only call Start/Stop on transitions.
    local wantPandemic = false
    if self.db.PandemicHighlight and self.selfAuraInstanceID > 0 and remaining > 0 and remaining <= PANDEMIC_WINDOW then
        wantPandemic = true
    end
    if wantPandemic and not self._pandemicActive then
        self:StartPandemicGlow()
        self._pandemicActive = true
    elseif not wantPandemic and self._pandemicActive then
        self:StopPandemicGlow()
        self._pandemicActive = false
    end

    self.countdownText:SetTextColor(tr, tg, tb, ta)
    if self.stateLabel then
        self.stateLabel:SetText(labelText)
        self.stateLabel:SetTextColor(tr, tg, tb, ta)
    end
    self:SetBorderStyle(borderColor, borderSize)

    -- Visibility: OnlyShowCrit hides non-crit casts, BUT the pandemic glow is
    -- a refresh cue — more important than a display preference — so we force
    -- the frame visible during the pandemic window even when OnlyShowCrit is
    -- on. Result: during a non-crit EM's last 4s, the frame reappears with
    -- BASE styling (the dupe branch above is gated on OnlyShowCrit so it
    -- can't paint here) and the pandemic glow overlaid. Works the same for
    -- Chronowarden and non-Chronowarden users — pandemic is decoupled from
    -- crit-talent state.
    local suppressForCritOnly = self.db.OnlyShowCrit and not self.isCrit
        and not self.isPreview and not wantPandemic
    if suppressForCritOnly then
        self:HideTracker()
    elseif self.selfAuraInstanceID > 0 or self.isPreview then
        self:ShowTracker()
    else
        self:HideTracker()
    end
end

---------------------------------------------------------------------------------
-- Ticker Management
---------------------------------------------------------------------------------
function EMT:TickerHandling()
    if self.selfAuraInstanceID > 0 then
        if not self.ticker then
            self.ticker = C_Timer.NewTicker(REFRESH_INTERVAL, function()
                self:UpdateDisplay()
            end)
        end
    else
        if self.ticker then
            self.ticker:Cancel()
            self.ticker = nil
        end
    end
end

function EMT:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

---------------------------------------------------------------------------------
-- Show / Hide (idempotent)
---------------------------------------------------------------------------------
function EMT:ShowTracker()
    if self._shown then return end
    self._shown = true
    if self.frame and not self.isPreview then
        self.frame:Show()
    end
end

function EMT:HideTracker()
    if not self._shown then return end
    self._shown = false
    if self.frame and not self.isPreview then
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function EMT:CreateFrames()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_EbonMightTracker", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(48, 48)
    frame:Hide()

    local iconFrame = CreateFrame("Frame", nil, frame)
    iconFrame:SetAllPoints(frame)

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconFrame)
    iconTex:SetTexture(ICON_ID)
    KE:ApplyIconZoom(iconTex)
    KE:AddIconBorders(iconFrame)

    local fontPath = KE:GetFontPath(self.db.FontFace)
    local wowOutline = KE:GetFontOutline(self.db.FontOutline) or ""
    local fontSize = self.db.FontSize or 22

    -- Countdown text inside the icon (Icon mode). Parent to iconFrame with
    -- sublevel 8 so it draws above the icon texture and border strips.
    local countdownText = iconFrame:CreateFontString(nil, "OVERLAY", nil, 8)
    countdownText:SetFont(fontPath, fontSize, wowOutline)
    countdownText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    countdownText:SetText("0")

    -- State label above the frame (Text mode). "CRIT" / "DUPE" / empty.
    local stateLabel = frame:CreateFontString(nil, "OVERLAY")
    stateLabel:SetFont(fontPath, fontSize, wowOutline)
    stateLabel:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    stateLabel:SetText("")
    stateLabel:Hide()

    self.frame         = frame
    self.iconFrame     = iconFrame
    self.iconTexture   = iconTex
    self.countdownText = countdownText
    self.stateLabel    = stateLabel
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function EMT:ApplySettings()
    if not self.frame then return end

    local size = self.db.IconSize or 48
    self.frame:SetSize(size, size)

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    if self.db.Strata then
        self.frame:SetFrameStrata(self.db.Strata)
    end

    KE:ApplyFontToText(self.countdownText, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
    KE:ApplyFontToText(self.stateLabel,    self.db.FontFace, self.db.FontSize, self.db.FontOutline)

    -- Mode-specific element visibility. Both elements always exist; we just
    -- toggle visibility so mode switches are cheap (no frame recreation).
    local isText = self.db.Mode == "text"
    if self.iconTexture then
        if isText then self.iconTexture:Hide() else self.iconTexture:Show() end
    end
    SetTextElementShown(self.countdownText, not isText)
    SetTextElementShown(self.stateLabel, isText)

    self:UpdateDisplay()
    -- Pick up glow-type / color changes mid-active. UpdateDisplay's edge-only
    -- Start/Stop won't fire when _pandemicActive hasn't transitioned.
    self:RefreshPandemicGlow()
end

---------------------------------------------------------------------------------
-- EditMode
---------------------------------------------------------------------------------
function EMT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "EbonMightTracker",
            displayName = "Ebon Might Tracker",
            frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "EbonMightTracker",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview Support
---------------------------------------------------------------------------------
function EMT:ShowPreview()
    if not self.frame then self:CreateFrames() end
    self:RegWithEditMode()
    self.isPreview = true
    self._shown = true
    self.selfAuraInstanceID = 1
    self.selfExpirationTime = GetTime() + 20
    self:ApplySettings()
    self.frame:Show()
end

function EMT:HidePreview()
    self.isPreview = false
    self._shown = false
    if not self.frame then return end
    self.frame:Hide()
    -- Re-sync with actual game state after the fake preview aura is cleared.
    self:ScanAuras()
    self:TickerHandling()
    self:UpdateDisplay()
end

---------------------------------------------------------------------------------
-- UNIT_AURA Handler
---------------------------------------------------------------------------------
function EMT:OnUnitAura(_, unit, updateInfo)
    if not self.db.Enabled or self.isPreview then return end
    if not self.isAugSpec then return end
    if not unit then return end

    -- Filter: only player, party, raid (not pets)
    if unit ~= "player" and not unit:find("^party%d") and not unit:find("^raid%d") then return end
    if unit:find("pet") then return end

    if not updateInfo then return end

    if updateInfo.isFullUpdate then
        self:ScanAuras()
        self:TickerHandling()
        self:UpdateDisplay()
        return
    end

    local changed = false

    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            if not issecretvalue(aura.applications) then
                -- EM on self
                if aura.spellId == EBON_MIGHT_SELF and aura.sourceUnit == "player" and unit == "player" then
                    self.selfAuraInstanceID = aura.auraInstanceID
                    if aura.expirationTime and not issecretvalue(aura.expirationTime) then
                        self.selfExpirationTime = aura.expirationTime
                    end
                    changed = true
                end
                -- EM on ally
                if self.inGroup and aura.spellId == EBON_MIGHT_OTHERS and aura.sourceUnit == "player" then
                    local value = self:BestPoint(aura) or 0
                    table.insert(self.ebonMight, {
                        auraId = aura.auraInstanceID,
                        value  = value,
                        target = unit,
                    })
                    -- UNIT_AURA event ordering isn't guaranteed — if the ally
                    -- aura event arrives before the self aura event, advance
                    -- selfExpirationTime via the ally aura so CalcCrit can tell
                    -- a new cast is in flight (ally + self auras have matching
                    -- expiration within a cast).
                    if aura.expirationTime and not issecretvalue(aura.expirationTime)
                       and aura.expirationTime > self.selfExpirationTime then
                        self.selfExpirationTime = aura.expirationTime
                    end
                    -- Cast-roll moment: this ally's aura just landed with the
                    -- cast's roll value baked in. Flag CalcCrit to (re)classify.
                    -- Additional ally adds for the same cast (staggered raid
                    -- application) re-set this flag; CalcCrit refreshes the
                    -- entry's normalization to match the higher count.
                    self._castNeedsPush = true
                    changed = true
                end
            end
        end
    end

    if updateInfo.updatedAuraInstanceIDs then
        for _, instanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
            -- Self update (refresh / extension)
            if instanceID == self.selfAuraInstanceID and unit == "player" then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instanceID)
                if auraData and auraData.expirationTime and not issecretvalue(auraData.expirationTime) then
                    self.selfExpirationTime = auraData.expirationTime
                    changed = true
                end
            end
            -- Ally update
            for _, em in ipairs(self.ebonMight) do
                if em.auraId == instanceID and em.target == unit then
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, instanceID)
                    if auraData then
                        local value = self:BestPoint(auraData)
                        if value and value > 0 then
                            em.value = value
                            changed = true
                        end
                    end
                end
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
            if instanceID == self.selfAuraInstanceID and unit == "player" then
                -- Self removal — wipe all state so a stale ally value can't
                -- poison the next cast's detection.
                self:ClearData()
                changed = true
            else
                -- Ally removal (guarded by unit — instance IDs are per-unit).
                for i = #self.ebonMight, 1, -1 do
                    local em = self.ebonMight[i]
                    if em.auraId == instanceID and em.target == unit then
                        table.remove(self.ebonMight, i)
                        changed = true
                    end
                end
            end
        end
    end

    if changed then
        self:TickerHandling()
        self:UpdateDisplay()
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function EMT:PLAYER_ENTERING_WORLD()
    self.isAugSpec = self:IsValidSpec()
    self:UpdateTalents()
    self.inGroup = IsInGroup()
    self:ScanAuras()
    self:AutoRefreshSeed()
    self:UpdateDisplay()
end

function EMT:PLAYER_REGEN_ENABLED()
    self:AutoRefreshSeed()
end

function EMT:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self.isAugSpec = self:IsValidSpec()
    self:UpdateTalents()
    if not self.isAugSpec then
        self:HideTracker()
        self:ClearData()
    else
        self:ScanAuras()
        self:UpdateDisplay()
    end
end

function EMT:TRAIT_CONFIG_UPDATED()
    self:UpdateTalents()
end

function EMT:GROUP_JOINED()
    self.inGroup = true
end

function EMT:GROUP_LEFT()
    self.inGroup = false
    self:ClearData()
    -- History was calibrated against group-cast values; solo content has
    -- no ally auras to compare so the history is stale on rejoin.
    wipe(self._castHistory)
    self._lastRecordedExpiration = 0
    self:UpdateDisplay()
end

function EMT:GROUP_ROSTER_UPDATE()
    self.inGroup = IsInGroup()
end

-- UNIT_FLAGS fires on death, charm, afk-enter, etc. Recompute whenever a
-- tracked group member's flags change so the state reflects current alive /
-- present members.
function EMT:UNIT_FLAGS(_, unit)
    if not self.isAugSpec or self.isPreview then return end
    if not unit then return end
    if unit ~= "player" and not unit:find("^party%d") and not unit:find("^raid%d") then return end
    if unit:find("pet") then return end
    self:UpdateDisplay()
end

-- PLAYER_TOTEM_UPDATE fires when the duplicate spawns or expires. Refresh
-- the display so the live `isDuped` flips immediately.
function EMT:PLAYER_TOTEM_UPDATE()
    if not self.isAugSpec or self.isPreview then return end
    self:UpdateDisplay()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function EMT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(self.db.Enabled == true)
end

function EMT:OnEnable()
    self:UpdateDB()
    -- Hard class gate: non-Evokers get no frame, no EditMode registration, no events.
    if not self.db.Enabled then return end
    if select(2, UnitClass("player")) ~= "EVOKER" then return end

    self:CreateFrames()
    self:RegWithEditMode()
    self:ApplySettings()
    self:RefreshSeed()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED")
    self:RegisterEvent("GROUP_JOINED")
    self:RegisterEvent("GROUP_LEFT")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("UNIT_FLAGS")
    self:RegisterEvent("PLAYER_TOTEM_UPDATE")
end

function EMT:OnDisable()
    self:UnregisterAllEvents()
    self:StopTicker()
    self:HideTracker()
    if self._pandemicActive then
        self:StopPandemicGlow()
        self._pandemicActive = false
    end
    self:ClearData()
    wipe(self._castHistory)
    self._lastRecordedExpiration = 0
    self._castNeedsPush = false
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/Detail.lua                                  ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: Out-of-combat in-window detail panel — per-    ║
-- ║           source spell breakdown + C_DeathRecap timeline.║
-- ║           Swaps in over the bar viewport on bar click;   ║
-- ║           gated to out of combat (spellID is secret in   ║
-- ║           combat, so C_Spell.* on it would taint).       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule
local DM = KitnEssentials:GetModule("DamageMeter")

local CreateFrame = CreateFrame
local C_Spell = C_Spell
local C_DamageMeter = C_DamageMeter
local Enum = Enum
local issecretvalue = issecretvalue
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local math_min, math_max = math.min, math.max
local format = string.format
local tostring = tostring
local pairs, ipairs = pairs, ipairs
local table_sort = table.sort

-- Same fixed pool ceiling as the main bars; the detail list never exceeds it.
local DETAIL_POOL_SIZE = DM.BAR_POOL_SIZE or 40

-- One detail row: [icon] name .......... value. Scripts wired ONCE (pool reuse).
-- Clicking any row closes the panel (the back gesture); mirrors EUI MakeSpellRow:1712.
local function MakeDetailRow(parent)
    local db = DM.db
    local bar = {}
    local row = CreateFrame("Button", nil, parent)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")
    bar.row = row

    row.fill = CreateFrame("StatusBar", nil, row)
    row.fill:SetAllPoints(row)
    row.fill:SetMinMaxValues(0, 1)
    row.fill:SetValue(0)
    row.fill:SetStatusBarTexture(KE:GetStatusbarPath(db and db.StatusBarTexture or "KitnUI"))

    -- Parent the icon frame to the row (not row.fill) so it tracks the row's
    -- frame bounds, matching Window.lua:MakeBar. Anchored to row:LEFT keeps it
    -- left-flush regardless of the fill's proportional width (a low-share fill
    -- can be only a few pixels wide and would clip a fill-parented icon).
    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon = row.iconFrame:CreateTexture(nil, "OVERLAY")
    row.icon:SetAllPoints(row.iconFrame)
    KE:ApplyIconZoom(row.icon)
    KE:AddIconBorders(row.iconFrame)
    row.iconFrame:Hide()

    local face = db and db.FontFace
    local size = db and db.FontSize
    local outline = db and db.FontOutline
    row.label = row.fill:CreateFontString(nil, "OVERLAY")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    KE:ApplyFontToText(row.label, face, size, outline)
    row.value = row.fill:CreateFontString(nil, "OVERLAY")
    row.value:SetPoint("RIGHT", row.fill, "RIGHT", -3, 0)
    row.value:SetJustifyH("RIGHT")
    KE:ApplyFontToText(row.value, face, size, outline)

    row:SetScript("OnClick", function() DM:CloseDetail(bar.win) end)
    row:Hide()
    return bar
end

-- Lazily builds W.detail (ScrollFrame viewport + content child + a create-once
-- spell-row pool) once, parented to W.frame and anchored over the same area as
-- W.body. Idempotent. Background click on the content closes the panel.
function DM:EnsureDetail(W)
    if W.detail then return W.detail end
    local d = CreateFrame("Frame", nil, W.frame)
    -- Cover the body area (header band stays visible; LayoutWindow owns _headerH).
    d:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 0, -(W._headerH or 18))
    d:SetPoint("BOTTOMRIGHT", W.frame, "BOTTOMRIGHT", 0, 0)
    d:EnableMouse(true)
    d:SetScript("OnMouseDown", function() DM:CloseDetail(W) end)
    d:Hide()

    d.view = CreateFrame("ScrollFrame", nil, d)
    d.view:SetAllPoints(d)
    d.content = CreateFrame("Frame", nil, d.view)
    d.content:SetSize(1, 1)
    d.view:SetScrollChild(d.content)
    d.view:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then d.content:SetWidth(w) end end)

    -- Mouse-wheel scroll for long breakdowns / recaps (Task 6). Step two rows per
    -- notch, clamped to [0, contentH - viewportH] so the wheel can't overscroll past
    -- the last row or above the top. All plain numbers (heights/stride are never
    -- secret); no-op when the list fits (maxScroll <= 0). Mirrors EUI 2289-2293.
    d.view:EnableMouseWheel(true)
    d.view:SetScript("OnMouseWheel", function(self, delta)
        local stride = W._snapStride or 18
        local viewH = self:GetHeight() or 0
        local contentH = d.content:GetHeight() or 0
        local maxScroll = contentH - viewH
        if maxScroll <= 0 then
            self:SetVerticalScroll(0)
            return
        end
        local cur = self:GetVerticalScroll() or 0
        local newScroll = cur - delta * (2 * stride)
        if newScroll < 0 then newScroll = 0
        elseif newScroll > maxScroll then newScroll = maxScroll end
        self:SetVerticalScroll(newScroll)
    end)

    d.rows = {}
    for i = 1, DETAIL_POOL_SIZE do
        local bar = MakeDetailRow(d.content)
        bar.win = W
        d.rows[i] = bar
    end
    W.detail = d
    return d
end

-- Right-click closes; left-click opens (out of combat only). bar carries the source
-- identity stashed by Window.lua RenderBar (Task 2).
function DM:OpenDetail(bar, button)
    local W = bar and bar.win
    if not W then return end
    -- The detail panel takes over the viewport; unconditionally clear the hover tip
    -- (and stop its poll) regardless of how we got here. ShowHoverTip early-returns
    -- on W._detailOpen, so without this the poll could spin idle if _detailOpen is
    -- set while a tip is still active via a non-OnLeave route.
    self:HideHoverTip()
    if button == "RightButton" then self:CloseDetail(W); return end

    if InCombatLockdown() then
        self:ShowDetailMessage(W, "Detailed information is\nsecret while in combat")
        return
    end

    self:EnsureDetail(W)
    W._detailSourceGUID = bar._sourceGUID
    W._detailSourceCID  = bar._sourceCreatureID
    W._detailRecapID    = bar._deathRecapID
    W._detailClass      = bar._classFilename
    W._detailOpen = true

    if W.body then W.body:Hide() end
    W.detail:Show()

    if W._isDeaths then
        self:RenderDeathRecap(W)
    else
        self:RenderBreakdown(W)
    end
end

function DM:CloseDetail(W)
    if not W or not W.detail then return end
    W._detailOpen = false
    W.detail:Hide()
    if W.body then W.body:Show() end
end

-- Reuses detail-row 1 as a centered message line (in-combat / no-recap states).
function DM:ShowDetailMessage(W, msg)
    -- Clear the hover tip before the detail message takes over (see OpenDetail):
    -- this sets W._detailOpen = true with no preceding OnLeave, so HideHoverTip
    -- here is what stops a still-active tip's poll.
    self:HideHoverTip()
    self:EnsureDetail(W)
    W._detailOpen = true
    if W.body then W.body:Hide() end
    W.detail:Show()
    for i = 1, DETAIL_POOL_SIZE do W.detail.rows[i].row:Hide() end
    if not W.detail.msg then
        W.detail.msg = W.detail.content:CreateFontString(nil, "OVERLAY")
        W.detail.msg:SetPoint("TOP", W.detail.content, "TOP", 0, -8)
        W.detail.msg:SetJustifyH("CENTER")
        KE:ApplyFontToText(W.detail.msg, self.db and self.db.FontFace, self.db and self.db.FontSize, self.db and self.db.FontOutline)
        W.detail.msg:SetTextColor(0.7, 0.7, 0.7)
    end
    W.detail.msg:SetText(msg)
    W.detail.msg:Show()
end

-- Per-source spell breakdown (out-of-combat only — OpenDetail is OOC-gated, so
-- spellID is plain here and C_Spell.* lookups don't taint). Port of EUI's standard
-- breakdown to KE helpers + the confirmed secret contract: amounts are plain OOC,
-- but percent math is still guarded with issecretvalue defensively (a stale combat
-- read could linger one frame). API pre-sorts combatSpells descending, so the index
-- IS the rank; maxAmount drives the proportional fill.
function DM:RenderBreakdown(W)
    if W.detail and W.detail.msg then W.detail.msg:Hide() end
    local cfg = self:ResolveWindowConfig(W.idx)
    if not cfg then return end

    -- Pull this source out of the window's active session. GetSource pcall-wraps the API.
    -- W._curSessionID: nil = live session; set by Task 6 history nav to a specific stored sessionID.
    local sessionID = W._curSessionID
    local src = self:GetSource(cfg.SessionType, cfg.MeterType, W._detailSourceGUID, W._detailSourceCID, sessionID)
    local spells = src and src.combatSpells
    local d = W.detail
    if not spells then
        for i = 1, DETAIL_POOL_SIZE do d.rows[i].row:Hide() end
        return
    end

    local stride = W._snapStride or 18
    local barH = W._snapHeight or 16
    local classColor = W._detailClass and RAID_CLASS_COLORS[W._detailClass]

    -- maxAmount drives the fill width. Out of combat amounts are plain numbers; gate
    -- percent on issecretvalue + type defensively before any arithmetic.
    local maxAmount = src.maxAmount
    local canPercent = maxAmount and (not issecretvalue(maxAmount)) and type(maxAmount) == "number"
        and src.totalAmount and not issecretvalue(src.totalAmount)
    local total = canPercent and src.totalAmount or 0

    -- DetailMaxRows (DB) caps the breakdown length; default 40 == pool size, so it is
    -- a no-op until a user lowers it. The recap timeline is deliberately NOT capped --
    -- a death recap should show every event leading to the death.
    local maxRows = (self.db and self.db.DetailMaxRows) or DETAIL_POOL_SIZE
    local count = math_min(#spells, DETAIL_POOL_SIZE, maxRows)
    for i = 1, DETAIL_POOL_SIZE do
        local bar = d.rows[i]
        local row = bar.row
        if i <= count then
            local spell = spells[i]
            row:ClearAllPoints()
            local yOff = -(i - 1) * stride
            row:SetPoint("TOPLEFT", d.content, "TOPLEFT", 0, yOff)
            row:SetPoint("TOPRIGHT", d.content, "TOPRIGHT", 0, yOff)
            row:SetHeight(barH)

            -- Icon from spellID (safe OUT of combat — spellID is secret IN combat).
            -- Falls back to a hidden icon frame if the lookup fails.
            local iconShown = false
            local spID = spell.spellID
            if spID and C_Spell and C_Spell.GetSpellTexture then
                -- pcall the lookup (parity with RenderDeathRecap) so a throw on an
                -- unknown/crafted spellID can't abort the row loop mid-render.
                local okT, tex = pcall(C_Spell.GetSpellTexture, spID)
                if okT and tex then
                    row.icon:SetTexture(tex)
                    KE:ApplyIconZoom(row.icon)
                    row.iconFrame:SetSize(barH, barH)
                    row.iconFrame:Show()
                    iconShown = true
                end
            end
            if not iconShown then row.iconFrame:Hide() end

            row.label:ClearAllPoints()
            if iconShown then
                row.label:SetPoint("LEFT", row.iconFrame, "RIGHT", 3, 0)
            else
                row.label:SetPoint("LEFT", row.fill, "LEFT", 3, 0)
            end
            row.label:SetPoint("RIGHT", row.value, "LEFT", -3, 0)

            -- Sanitize the per-spell amount before any Lua math/format. SetValue
            -- accepts secrets (raw amount feeds the fill), but the percent path and
            -- FormatBarValue's plain-string branch must run on a non-secret number.
            -- Mirrors EllesmereUI's per-spell issecretvalue sanitize into a plain local.
            local amt = spell.totalAmount
            local amtPlain = amt
            if issecretvalue(amt) or type(amt) ~= "number" then amtPlain = 0 end

            -- Fill: class-colored (source's class), width by amount.
            row.fill:SetMinMaxValues(0, maxAmount or 1)
            row.fill:SetValue(amt or 0)
            if classColor then
                row.fill:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            else
                local ar, ag, ab = KE:GetAccentColor()
                row.fill:SetStatusBarColor(ar or 0.6, ag or 0.6, ab or 0.6)
            end

            -- Name: GetSpellName (secret-guard the RETURN), fall back to creatureName/Unknown.
            local nm
            if spID then
                local ok, sn = pcall(C_Spell.GetSpellName, spID)
                if ok and sn and not issecretvalue(sn) then nm = sn end
            end
            row.label:SetText(nm or spell.creatureName or "Unknown")

            -- Value: abbreviated amount + percent (when computable). FormatBarValue
            -- uses AbbreviateNumbers (AllowedWhenTainted) for parity with the main bars.
            -- Percent arithmetic runs on amtPlain (sanitized) so a stray secret amount
            -- cannot taint via division/format; the source aggregates are also guarded.
            local amtStr = (self.FormatBarValue and select(1, self.FormatBarValue(amtPlain, nil, false))) or ""
            if canPercent and total > 0 then
                row.value:SetText(format("%s  %.1f%%", amtStr, (amtPlain / total) * 100))
            else
                row.value:SetText(amtStr)
            end

            if not row:IsShown() then row:Show() end
        else
            if row:IsShown() then row:Hide() end
        end
    end

    -- Size the scroll child so the wheel can scroll long lists (Task 6 wires the wheel).
    d.content:SetHeight(math_max(10, count * stride))
end

-- Death-recap timeline (out-of-combat only — OpenDetail is OOC-gated). Renders the
-- source's C_DeathRecap events oldest-first: each row is one combat-log event leading
-- to the death, with the HP-remaining fill, "-Xs SpellName from Source" label, and a
-- +heal / -damage value (crit marker, killing-blow overkill, HP% suffix). Recap fields
-- use spellId (lowercase d) — distinct from combatSpells' spellID. Three-tier gate is
-- in DM:GetDeathRecap (no/secret/<=0 recapID, no events) which returns nil -> message.
function DM:RenderDeathRecap(W)
    if W.detail and W.detail.msg then W.detail.msg:Hide() end
    local d = W.detail
    local events, maxHP = self:GetDeathRecap(W._detailRecapID)
    if not events then
        self:ShowDetailMessage(W, "No death recap available")
        return
    end

    local stride = W._snapStride or 18
    local barH = W._snapHeight or 16
    local deathTime = events[#events] and events[#events].timestamp
    local count = math_min(#events, DETAIL_POOL_SIZE)

    for i = 1, DETAIL_POOL_SIZE do
        local bar = d.rows[i]
        local row = bar.row
        if i <= count then
            local ev = events[i]
            row:ClearAllPoints()
            local yOff = -(i - 1) * stride
            row:SetPoint("TOPLEFT", d.content, "TOPLEFT", 0, yOff)
            row:SetPoint("TOPRIGHT", d.content, "TOPRIGHT", 0, yOff)
            row:SetHeight(barH)

            -- Icon: spellId (lowercase d on recap events); pcall the lookup (parity with
            -- RenderBreakdown's GetSpellName) so a throw can't abort the loop mid-render and
            -- leave the row pool half-shown. Any failure (nil OR error) -> melee fallback 135274.
            local spID = ev.spellId
            local tex = 135274
            if spID and spID > 0 and C_Spell and C_Spell.GetSpellTexture then
                local okT, t = pcall(C_Spell.GetSpellTexture, spID)
                if okT and t then tex = t end
            end
            row.icon:SetTexture(tex)
            KE:ApplyIconZoom(row.icon)
            row.iconFrame:SetSize(barH, barH)
            row.iconFrame:Show()
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row.iconFrame, "RIGHT", 3, 0)
            row.label:SetPoint("RIGHT", row.value, "LEFT", -3, 0)

            local evType = ev.event or ""
            local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
            local isFatal = (i == count and not isHeal)

            -- Fill = HP% remaining at the event (currentHP / maxHP), heal green / damage red.
            -- GetRecapEvents is AllowedWhenUntainted, so ev.currentHP can be a secret number
            -- in a tainted post-combat window -- sanitize before the division (matches ev.amount).
            local curHP = ev.currentHP
            if issecretvalue(curHP) or type(curHP) ~= "number" then curHP = 0 end
            local hpPct = math_min(1, math_max(0, maxHP > 0 and (curHP / maxHP) or 0))
            row.fill:SetMinMaxValues(0, 1)
            row.fill:SetValue(hpPct)
            if isHeal then row.fill:SetStatusBarColor(0.10, 0.50, 0.10)
            else row.fill:SetStatusBarColor(0.60, 0.08, 0.08) end

            -- Label: "-X.Xs SpellName" (+ " (Source)" when a non-secret sourceName exists).
            -- Parens form matches Details and the hover-tip recap surface (Phase 4c).
            local spellName = ev.spellName
            if not spellName or issecretvalue(spellName) or spellName == "" then
                if isHeal then spellName = "Heal"
                elseif evType == "SWING_DAMAGE" then spellName = "Melee"
                else spellName = "Unknown" end
            end
            local label = self.FormatRecapDelta(deathTime, ev.timestamp) .. " " .. spellName
            local srcName = ev.sourceName
            if srcName and not issecretvalue(srcName) and srcName ~= "" and not isHeal then
                label = label .. "  |cff999999(" .. srcName .. ")|r"
            end
            row.label:SetText(label)

            -- Value: +heal / -damage (AbbreviateNumbers is AllowedWhenTainted), crit marker,
            -- overkill on the killing blow, HP% suffix.
            -- C_DeathRecap.GetRecapEvents is AllowedWhenUntainted, so ev.amount can be a
            -- secret number if a tainted execution slips into the brief post-combat window.
            -- Arithmetic (math_max) must run on a sanitized plain number; the raw amt is
            -- never math'd here (FormatBarValue's plain branch and tostring also use amtPlain).
            local amt = ev.amount or 0
            local amtPlain = amt
            if issecretvalue(amt) or type(amt) ~= "number" then amtPlain = 0 end
            local body = (self.FormatBarValue and select(1, self.FormatBarValue(math_max(0, amtPlain), nil, false))) or tostring(amtPlain)
            local sign = isHeal and "+" or "-"
            -- ev.critical is AllowedWhenUntainted (same window as ev.amount, line 349).
            -- A boolean-truthiness test on a secret BOOLEAN throws -- sanitize to a plain
            -- bool first (issecretvalue gate) so the marker test never touches a secret.
            local critFlag = (not issecretvalue(ev.critical)) and ev.critical or false
            local crit = critFlag and " |cffffd100*|r" or ""
            local pctSuffix = format(" (%.0f%%)", hpPct * 100)
            if isFatal and not issecretvalue(ev.overkill) and type(ev.overkill) == "number" and ev.overkill > 0 then
                local okStr = (self.FormatBarValue and select(1, self.FormatBarValue(ev.overkill, nil, false))) or tostring(ev.overkill)
                row.value:SetText(sign .. body .. crit .. " |cffff3333(" .. okStr .. " overkill)|r" .. pctSuffix)
            else
                row.value:SetText(sign .. body .. crit .. pctSuffix)
            end

            if not row:IsShown() then row:Show() end
        else
            if row:IsShown() then row:Hide() end
        end
    end
    d.content:SetHeight(math_max(10, count * stride))
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Damage-Done targets (Phase 4c / Task 12)               ║
-- ║  Cross-references the EnemyDamageTaken session to build  ║
-- ║  a map of ALL players' damage per enemy in ONE pass --   ║
-- ║  the first hover triggers the build, every subsequent    ║
-- ║  hover (any player) is an instant cache lookup. Out-of-  ║
-- ║  combat only (PopulateHoverTip is OOC-gated before this  ║
-- ║  is reached); enemy.name is ConditionalSecret -> only    ║
-- ║  ever SetText, never compared; det.unitName guarded.     ║
-- ║  Cache keyed by session|sessionID, self-invalidating on  ║
-- ║  a session change + explicitly cleared on reset.         ║
-- ╚══════════════════════════════════════════════════════════╝

-- { key = "session|sessionID", map = { [playerName] = sorted {name,total} } }
local _targetsCache = {}

-- Drop the cached targets map so the next hover rebuilds it. Called from the
-- session-reset paths in Core.lua (DM:OnMeterReset / DM:HeaderReset) -- a stored
-- session that gets wiped would otherwise serve stale enemy totals until the
-- session|sessionID cache key happens to change. Public on DM (Core resolves it
-- at runtime, same as the render-chunk methods).
function DM:InvalidateTargetsCache()
    _targetsCache.key = nil
    _targetsCache.map = nil
end

-- One full pass over the EnemyDamageTaken session: for every enemy combatSource
-- walk its combatSpells and accumulate spell.totalAmount per (player, enemy),
-- keyed by the enemy's sourceCreatureID (NeverSecret numeric; falls back to the
-- loop index if it is somehow secret) so a secret value never becomes a table key.
-- Builds, per player, a sorted descending {name=enemyName, total=amount} list.
-- Cached by session|sessionID -- the cache key self-invalidates whenever the
-- pinned/live session changes. Port of EllesmereUI BuildAllPlayerTargets:795-864.
local function BuildAllPlayerTargets(session, sessionID)
    local cacheKey = tostring(session) .. "|" .. tostring(sessionID)
    if _targetsCache.key == cacheKey then return _targetsCache.map end

    if not C_DamageMeter then return nil end
    local enemyType = Enum.DamageMeterType.EnemyDamageTaken

    -- Pull the EnemyDamageTaken session (FromID for a pinned session, else FromType
    -- for the live one); both pcall'd -- the API can reject while execution is tainted.
    local enemySession
    if sessionID ~= nil and C_DamageMeter.GetCombatSessionFromID then
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, enemyType)
        if ok then enemySession = s end
    elseif C_DamageMeter.GetCombatSessionFromType then
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, session, enemyType)
        if ok then enemySession = s end
    end
    if not enemySession or not enemySession.combatSources or #enemySession.combatSources == 0 then
        _targetsCache.key = cacheKey
        _targetsCache.map = nil
        return nil
    end

    local enemyNames = {}   -- enemyKey -> display name (ConditionalSecret; SetText only)
    local enemyTotals = {}  -- enemyKey -> total damage that enemy took from EVERYONE (enemy-share % denominator)
    local byPlayer = {}     -- playerName -> { [enemyKey] = { total = amount, dps = amountPerSecond } }
    for ei = 1, #enemySession.combatSources do
        local enemy = enemySession.combatSources[ei]
        local rawCID = enemy.sourceCreatureID
        -- Enemy key: the NeverSecret creatureID, or the loop index if it is secret --
        -- a secret value must never be used as a table key (taint).
        local eKey = (rawCID and not issecretvalue(rawCID)) and rawCID or ei
        enemyNames[eKey] = enemy.name
        -- enemy.totalAmount is the enemy's whole damage-taken; sanitize before storing as the
        -- %-denominator (OOC path, but guard defensively against a stale secret read).
        local etot = enemy.totalAmount
        if issecretvalue(etot) or type(etot) ~= "number" then etot = 0 end
        enemyTotals[eKey] = etot

        local srcData
        if sessionID ~= nil and C_DamageMeter.GetCombatSessionSourceFromID then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, enemyType, enemy.sourceGUID, enemy.sourceCreatureID)
            if ok then srcData = sd end
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromType, session, enemyType, enemy.sourceGUID, enemy.sourceCreatureID)
            if ok then srcData = sd end
        end

        if srcData and srcData.combatSpells then
            for _, spell in ipairs(srcData.combatSpells) do
                local det = spell.combatSpellDetails
                -- det.unitName (the attacking player) is the per-player key. Guard the
                -- secret read before using it as a key; sanitize the amount before > 0.
                if det and det.unitName and not issecretvalue(det.unitName) then
                    local pName = det.unitName
                    local amt = spell.totalAmount
                    if issecretvalue(amt) or type(amt) ~= "number" then amt = 0 end
                    -- amountPerSecond accumulates into the per-target DPS column. Summing each
                    -- spell's per-second over a target == that player's aggregate DPS to it
                    -- (every spell shares the same combat-duration denominator). Sanitized like amt.
                    local ps = spell.amountPerSecond
                    if issecretvalue(ps) or type(ps) ~= "number" then ps = 0 end
                    if amt > 0 then
                        local pt = byPlayer[pName]
                        if not pt then pt = {}; byPlayer[pName] = pt end
                        local e = pt[eKey]
                        if not e then e = { total = 0, dps = 0 }; pt[eKey] = e end
                        e.total = e.total + amt
                        e.dps = e.dps + ps
                    end
                end
            end
        end
    end

    -- Flatten each player's enemy map into a descending-sorted array. Each entry carries the
    -- raw amount + accumulated DPS (both plain numbers by construction) and an enemy-share
    -- percent: this player's damage / the enemy's whole damage-taken (nil when the denominator
    -- is unavailable). Mirrors the Details-style "% of this target you accounted for".
    local map = {}
    for pName, enemies in pairs(byPlayer) do
        local list = {}
        for eKey, e in pairs(enemies) do
            local etot = enemyTotals[eKey] or 0
            local pct = (etot > 0) and (e.total / etot * 100) or nil
            list[#list + 1] = { name = enemyNames[eKey], total = e.total, dps = e.dps, pct = pct }
        end
        table_sort(list, function(a, b) return a.total > b.total end)
        map[pName] = list
    end

    _targetsCache.key = cacheKey
    _targetsCache.map = map
    return map
end

-- Top `maxTargets` enemies a single player hit, sorted descending, or nil. The
-- player name is the breakdown source's plain (non-secret) name; guard it before
-- the table lookup (a secret string can't be a key). Port of EUI BuildPlayerTargets:866-886.
local function BuildPlayerTargets(playerName, session, sessionID, maxTargets)
    if not playerName or issecretvalue(playerName) or playerName == "" then return nil end

    local map = BuildAllPlayerTargets(session, sessionID)
    if not map then return nil end

    local list = map[playerName]
    if not list or #list == 0 then return nil end

    if #list > maxTargets then
        local trimmed = {}
        for i = 1, maxTargets do trimmed[i] = list[i] end
        return trimmed
    end
    return list
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Hover quick-peek tooltip (Phase 4b / Task 9)            ║
-- ║  A single module-level tip (shared by every window, like ║
-- ║  EUI) shown on bar OnEnter: the top few breakdown spells  ║
-- ║  (or recap events for a Deaths window). Built lazily,     ║
-- ║  TOOLTIP strata, parented to UIParent, passive (never     ║
-- ║  intercepts the mouse). A detach-when-idle poll keeps the ║
-- ║  numbers live while a bar is hovered. UNLIKE the click-   ║
-- ║  inline panel a hover fires IN COMBAT, so the populate    ║
-- ║  path hard-gates on InCombatLockdown BEFORE any secret    ║
-- ║  read (spellID is secret in combat -> touching it taints).║
-- ╚══════════════════════════════════════════════════════════╝

local HOVER_TIP_ROWS = 15       -- top spells/events (matches EUI's TT_MAX=15); the click-inline panel still shows the full list
local TIP_WIDTH = 300           -- Phase 4c: widened for the 3 content-sized numeric columns (Amount / DPS / %) + spell-name room
local TIP_PAD = 4               -- inner inset for header / rows

-- Phase 4c column geometry: each numeric column is right-aligned at a fixed x-offset
-- from the tip's right edge. Content-sized (no SetWidth) + SetWordWrap(false) so the
-- text never truncates with an ellipsis at the user's font size; the label's RIGHT anchor
-- stops at the amount column's LEFT so the three columns line up across every row + header.
local TIP_PCT_X   = -6          -- % column right edge
local TIP_DPS_X   = -62         -- DPS column right edge (widened from -48 so content-sized columns don't collide)
local TIP_AMT_X   = -124        -- Amount column right edge (widened from -96)
local TIP_COL_HDR_H = 14        -- vertical space the column-header row occupies (breakdown path only)
local TIP_TGT_ROWS = 3          -- Phase 4c: top enemies the source hit (DamageDone-only sub-section)
local TIP_TGT_GAP = 4           -- vertical gap above the Targets divider
local TIP_TGT_LABEL_H = 12      -- height the "Targets" label occupies before the target rows
local _tip                      -- module-level singleton (shared by all windows)
local _tipActiveBar             -- the bar currently hovered (nil = none); drives the poll
local _tipPoll                  -- detach-when-idle OnUpdate frame
local _tipPollAccum = 0

-- One tip row: [icon] name .......... value. Same anatomy as MakeDetailRow but
-- parented to the tip and laid out by index (the tip is fixed-width, no scroll).
-- Scripts are NOT wired here -- the tip is passive (EnableMouse(false)), so a row
-- never receives clicks; it is a pure display element.
local function MakeTipRow(parent, rowH)
    local db = DM.db
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(rowH)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", TIP_PAD, 0)   -- y set by PopulateHoverTip
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -TIP_PAD, 0)

    row.fill = CreateFrame("StatusBar", nil, row)
    row.fill:SetAllPoints(row)
    row.fill:SetMinMaxValues(0, 1)
    row.fill:SetValue(0)
    row.fill:SetStatusBarTexture(KE:GetStatusbarPath(db and db.StatusBarTexture or "KitnUI"))

    -- Icon frame parented to the row (not row.fill) so it tracks the row bounds
    -- regardless of the fill's proportional width -- same reasoning as MakeDetailRow.
    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.iconFrame:SetSize(rowH, rowH)
    row.icon = row.iconFrame:CreateTexture(nil, "OVERLAY")
    row.icon:SetAllPoints(row.iconFrame)
    KE:ApplyIconZoom(row.icon)
    KE:AddIconBorders(row.iconFrame)
    row.iconFrame:Hide()

    local face = db and db.FontFace
    local size = db and db.FontSize
    local outline = db and db.FontOutline
    row.label = row.fill:CreateFontString(nil, "OVERLAY")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    KE:ApplyFontToText(row.label, face, size, outline)

    -- Phase 4c: three right-aligned numeric columns (Amount / DPS / %). row.value is the
    -- Amount column (renamed-in-role from the old single value). For the Deaths recap path
    -- only row.value is used (dps/pct stay empty + hidden); the breakdown path fills all three.
    -- Content-sized (no SetWidth) + SetWordWrap(false): right-anchored, so each column
    -- sizes to its text and never truncates with an ellipsis at the user's font size.
    row.value = row.fill:CreateFontString(nil, "OVERLAY")   -- Amount column
    row.value:SetPoint("RIGHT", row.fill, "RIGHT", TIP_AMT_X, 0)
    row.value:SetWordWrap(false)
    row.value:SetJustifyH("RIGHT")
    KE:ApplyFontToText(row.value, face, size, outline)

    row.dps = row.fill:CreateFontString(nil, "OVERLAY")     -- DPS column
    row.dps:SetPoint("RIGHT", row.fill, "RIGHT", TIP_DPS_X, 0)
    row.dps:SetWordWrap(false)
    row.dps:SetJustifyH("RIGHT")
    KE:ApplyFontToText(row.dps, face, size, outline)

    row.pct = row.fill:CreateFontString(nil, "OVERLAY")     -- % column
    row.pct:SetPoint("RIGHT", row.fill, "RIGHT", TIP_PCT_X, 0)
    row.pct:SetWordWrap(false)
    row.pct:SetJustifyH("RIGHT")
    KE:ApplyFontToText(row.pct, face, size, outline)

    row:Hide()
    return { row = row }
end

-- One Targets-sub-section row: [fill] enemyName .... Amount  DPS  %. No icon, but the three
-- numeric columns line up under the SAME fixed offsets as the spell rows (TIP_AMT_X / DPS / PCT)
-- so the breakdown and Targets share one column grid (request 2026-06-05). Passive like the rest
-- of the tip. Content-sized columns (no SetWidth) + SetWordWrap(false) so nothing truncates.
local function MakeTargetRow(parent, rowH)
    local db = DM.db
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(rowH)

    row.fill = CreateFrame("StatusBar", nil, row)
    row.fill:SetAllPoints(row)
    row.fill:SetMinMaxValues(0, 1)
    row.fill:SetValue(0)
    row.fill:SetStatusBarTexture(KE:GetStatusbarPath(db and db.StatusBarTexture or "KitnUI"))

    local face = db and db.FontFace
    local size = db and db.FontSize
    local outline = db and db.FontOutline
    row.label = row.fill:CreateFontString(nil, "OVERLAY")
    row.label:SetPoint("LEFT", row.fill, "LEFT", 3, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    KE:ApplyFontToText(row.label, face, size, outline)

    row.value = row.fill:CreateFontString(nil, "OVERLAY")   -- Amount column
    row.value:SetPoint("RIGHT", row.fill, "RIGHT", TIP_AMT_X, 0)
    row.value:SetWordWrap(false)
    row.value:SetJustifyH("RIGHT")
    KE:ApplyFontToText(row.value, face, size, outline)

    row.dps = row.fill:CreateFontString(nil, "OVERLAY")     -- DPS column
    row.dps:SetPoint("RIGHT", row.fill, "RIGHT", TIP_DPS_X, 0)
    row.dps:SetWordWrap(false)
    row.dps:SetJustifyH("RIGHT")
    KE:ApplyFontToText(row.dps, face, size, outline)

    row.pct = row.fill:CreateFontString(nil, "OVERLAY")     -- % column
    row.pct:SetPoint("RIGHT", row.fill, "RIGHT", TIP_PCT_X, 0)
    row.pct:SetWordWrap(false)
    row.pct:SetJustifyH("RIGHT")
    KE:ApplyFontToText(row.pct, face, size, outline)

    row.label:SetPoint("RIGHT", row.value, "LEFT", -3, 0)

    row:Hide()
    return { row = row }
end

-- Lazily build the shared tip frame. Matches the window/detail backdrop styling so
-- the peek reads as part of the meter. EnableMouse(false): it is a passive overlay
-- and must never steal the hover from the bar underneath (which is what keeps it open).
function DM:EnsureHoverTip()
    if _tip then return _tip end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:SetWidth(TIP_WIDTH)
    f:SetHeight(20)
    f:EnableMouse(false)
    f:Hide()

    -- Backdrop: reuse the meter's flat bg/border so the tip matches the window
    -- chrome. A fresh cfg table (cached on _tip) fed to KE:ApplyBackdrop.
    local db = self.db
    f._backdropCfg = {
        Enabled = true,
        BorderSize = 1,
        Color = (db and db.BackdropColor) or { 0.031, 0.031, 0.031, 0.95 },
        BorderColor = (db and db.BackdropBorderColor) or { 0, 0, 0, 1 },
    }
    KE:ApplyBackdrop(f, f._backdropCfg)

    local face = db and db.FontFace
    local size = db and db.FontSize
    local outline = db and db.FontOutline

    -- Source-name title: CENTERED + class-colored (request 2026-06-05). The class tint
    -- is applied per-populate from bar._classFilename (PopulateHoverTip); centering makes
    -- the name read as a title so the column-category labels below can be the white headers.
    f.header = f:CreateFontString(nil, "OVERLAY")
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", TIP_PAD, -TIP_PAD)
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -TIP_PAD, -TIP_PAD)
    f.header:SetJustifyH("CENTER")
    f.header:SetWordWrap(false)
    KE:ApplyFontToText(f.header, face, size, outline)

    -- Phase 4c: one-time column-header row (Spell · Amount · DPS · %) under the source
    -- name. The category labels are now WHITE and one notch larger than before (request
    -- 2026-06-05: the centered class-colored title frees them to be the prominent headers),
    -- right-aligned over the same fixed columns as the data rows. Shown for the breakdown
    -- path, hidden for the Deaths recap (which keeps a single value column). Anchored just
    -- below the source header; PopulateHoverTip toggles it and offsets the data rows by
    -- COL_HDR_H when visible.
    local colSize = math.max(9, (size or 12) - 1)   -- white header, slightly larger than the old size-2 gray
    f.colHdr = {}
    f.colHdr.spell = f:CreateFontString(nil, "OVERLAY")
    f.colHdr.spell:SetJustifyH("LEFT")
    f.colHdr.spell:SetWordWrap(false)
    f.colHdr.spell:SetPoint("TOPLEFT", f, "TOPLEFT", TIP_PAD, 0)   -- y set in PopulateHoverTip
    KE:ApplyFontToText(f.colHdr.spell, face, colSize, outline)
    f.colHdr.spell:SetTextColor(1, 1, 1)
    f.colHdr.spell:SetText("Spell")

    f.colHdr.amount = f:CreateFontString(nil, "OVERLAY")
    f.colHdr.amount:SetJustifyH("RIGHT")
    f.colHdr.amount:SetWordWrap(false)
    f.colHdr.amount:SetPoint("TOPRIGHT", f, "TOPRIGHT", TIP_AMT_X, 0)
    KE:ApplyFontToText(f.colHdr.amount, face, colSize, outline)
    f.colHdr.amount:SetTextColor(1, 1, 1)
    f.colHdr.amount:SetText("Amount")
    -- Cap the Spell label at the Amount column's left edge so it can't run into the
    -- numeric headers at large colSize / wide fonts (mirrors the row-label RIGHT stop).
    f.colHdr.spell:SetPoint("TOPRIGHT", f.colHdr.amount, "TOPLEFT", -3, 0)

    f.colHdr.dps = f:CreateFontString(nil, "OVERLAY")
    f.colHdr.dps:SetJustifyH("RIGHT")
    f.colHdr.dps:SetWordWrap(false)
    f.colHdr.dps:SetPoint("TOPRIGHT", f, "TOPRIGHT", TIP_DPS_X, 0)
    KE:ApplyFontToText(f.colHdr.dps, face, colSize, outline)
    f.colHdr.dps:SetTextColor(1, 1, 1)
    f.colHdr.dps:SetText("DPS")

    f.colHdr.pct = f:CreateFontString(nil, "OVERLAY")
    f.colHdr.pct:SetJustifyH("RIGHT")
    f.colHdr.pct:SetWordWrap(false)
    f.colHdr.pct:SetPoint("TOPRIGHT", f, "TOPRIGHT", TIP_PCT_X, 0)
    KE:ApplyFontToText(f.colHdr.pct, face, colSize, outline)
    f.colHdr.pct:SetTextColor(1, 1, 1)
    f.colHdr.pct:SetText("%")

    -- Centered gray message line (the in-combat "secret" state).
    f.msg = f:CreateFontString(nil, "OVERLAY")
    f.msg:SetPoint("TOP", f, "TOP", 0, -(TIP_PAD * 2 + (size or 12)))
    f.msg:SetJustifyH("CENTER")
    KE:ApplyFontToText(f.msg, face, size, outline)
    f.msg:SetTextColor(0.7, 0.7, 0.7)
    f.msg:Hide()

    f.rows = {}
    local rowH = (self.windows_rt and self.windows_rt[1] and self.windows_rt[1]._snapHeight) or 16
    for i = 1, HOVER_TIP_ROWS do
        f.rows[i] = MakeTipRow(f, rowH)
    end

    _tip = f
    return f
end

-- Hide every Targets-sub-section element. Cheap; called whenever the section is
-- not applicable (recap path, non-DamageDone meter, no targets, in combat).
local function HideTipTargets()
    if not (_tip and _tip.tgtDivider) then return end
    _tip.tgtDivider:Hide()
    _tip.tgtLabel:Hide()
    if _tip.tgtIcon then _tip.tgtIcon:Hide() end
    if _tip.tgtHdrAmount then _tip.tgtHdrAmount:Hide(); _tip.tgtHdrDps:Hide(); _tip.tgtHdrPct:Hide() end
    for ti = 1, TIP_TGT_ROWS do _tip.tgtRows[ti].row:Hide() end
end

-- Render the "Targets" sub-section (top enemies this source hit) below the spell
-- rows. `topY` is the y-offset (negative, from the tip TOPLEFT) of the first free
-- slot below the breakdown. Returns the extra height the section consumed (0 when
-- nothing is shown). Lazy-creates the divider/label/rows once. DamageDone-only +
-- breakdown-path-only; the caller gates that. Port of EUI render 1207-1265.
local function RenderTipTargets(self, bar, cfg, sessionID, topY, stride, barH)
    -- Key the per-player lookup on the RAW (unstripped) source name: BuildAllPlayerTargets
    -- keys byPlayer on the raw det.unitName, which carries the "-Realm" suffix for
    -- cross-realm members. bar._cachedName loses that suffix when ShowRealm is off
    -- (the default), so it would miss; bar._rawName preserves it. Mirrors EUI's raw-name
    -- lookup (realm stripped for display only, never for the targets key).
    local targets = BuildPlayerTargets(bar._rawName, cfg.SessionType, sessionID, TIP_TGT_ROWS)
    if not targets then
        HideTipTargets()
        return 0
    end

    -- Lazy-create the divider + section-header (icon + "Targets" + repeated Amount/DPS/%
    -- column headers) + up to TIP_TGT_ROWS bars once. The repeated numeric headers + dm_deaths
    -- icon make the Targets section mirror the spell section, matching Details (request 2026-06-05).
    if not _tip.tgtDivider then
        _tip.tgtDivider = _tip:CreateTexture(nil, "ARTWORK")
        _tip.tgtDivider:SetHeight(1)
        _tip.tgtDivider:SetColorTexture(1, 1, 1, 0.15)

        local db = DM.db
        local face, size, outline = db and db.FontFace, db and db.FontSize, db and db.FontOutline
        local lblSize = math_max(9, (size or 12) - 1)   -- match the top column headers (white, size-1)

        -- dm_deaths icon to the LEFT of the "Targets" label (Details places a section icon there).
        _tip.tgtIcon = _tip:CreateTexture(nil, "OVERLAY")
        _tip.tgtIcon:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\Icon\\dm_deaths.tga")
        _tip.tgtIcon:SetSize(lblSize + 3, lblSize + 3)

        _tip.tgtLabel = _tip:CreateFontString(nil, "OVERLAY")
        _tip.tgtLabel:SetJustifyH("LEFT")
        _tip.tgtLabel:SetWordWrap(false)
        KE:ApplyFontToText(_tip.tgtLabel, face, lblSize, outline)
        _tip.tgtLabel:SetTextColor(1, 1, 1)
        _tip.tgtLabel:SetText("Targets")

        -- Repeated numeric column headers over the same fixed columns as the spell headers.
        local function MakeTgtHdr(text, xOff)
            local fs = _tip:CreateFontString(nil, "OVERLAY")
            fs:SetJustifyH("RIGHT")
            fs:SetWordWrap(false)
            KE:ApplyFontToText(fs, face, lblSize, outline)
            fs:SetTextColor(1, 1, 1)
            fs:SetText(text)
            fs._xOff = xOff
            return fs
        end
        _tip.tgtHdrAmount = MakeTgtHdr("Amount", TIP_AMT_X)
        _tip.tgtHdrDps = MakeTgtHdr("DPS", TIP_DPS_X)
        _tip.tgtHdrPct = MakeTgtHdr("%", TIP_PCT_X)

        _tip.tgtRows = {}
        for ti = 1, TIP_TGT_ROWS do
            _tip.tgtRows[ti] = MakeTargetRow(_tip, barH)
        end
    end

    -- Divider just below the spell rows, then the label, then the target bars.
    local divY = topY - TIP_TGT_GAP
    _tip.tgtDivider:ClearAllPoints()
    _tip.tgtDivider:SetPoint("TOPLEFT", _tip, "TOPLEFT", TIP_PAD, divY)
    _tip.tgtDivider:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", -TIP_PAD, divY)
    _tip.tgtDivider:Show()

    local lblY = divY - 2
    local iconSz = _tip.tgtIcon:GetWidth() or 12
    -- "Targets" label sits right of the icon; the icon is vertically centered on it.
    _tip.tgtLabel:ClearAllPoints()
    _tip.tgtLabel:SetPoint("TOPLEFT", _tip, "TOPLEFT", TIP_PAD + iconSz + 3, lblY)
    _tip.tgtLabel:Show()
    _tip.tgtIcon:ClearAllPoints()
    _tip.tgtIcon:SetPoint("RIGHT", _tip.tgtLabel, "LEFT", -3, 0)
    _tip.tgtIcon:Show()
    -- Repeated Amount/DPS/% headers over the shared columns (same offsets as the spell headers).
    _tip.tgtHdrAmount:ClearAllPoints(); _tip.tgtHdrAmount:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", _tip.tgtHdrAmount._xOff, lblY); _tip.tgtHdrAmount:Show()
    _tip.tgtHdrDps:ClearAllPoints();    _tip.tgtHdrDps:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", _tip.tgtHdrDps._xOff, lblY); _tip.tgtHdrDps:Show()
    _tip.tgtHdrPct:ClearAllPoints();    _tip.tgtHdrPct:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", _tip.tgtHdrPct._xOff, lblY); _tip.tgtHdrPct:Show()

    -- targets[1].total is a plain number (sanitized accumulation in BuildAllPlayerTargets),
    -- safe to feed SetMinMaxValues. enemy name is ConditionalSecret -> SetText only.
    local rowsTop = lblY - TIP_TGT_LABEL_H
    local tMax = targets[1].total
    if tMax <= 0 then tMax = 1 end
    local shownTargets = 0
    for ti = 1, TIP_TGT_ROWS do
        local tr = _tip.tgtRows[ti]
        local row = tr.row
        if ti <= #targets then
            local t = targets[ti]
            local yOff = rowsTop - (ti - 1) * stride
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", _tip, "TOPLEFT", TIP_PAD, yOff)
            row:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", -TIP_PAD, yOff)
            row:SetHeight(barH)
            row.fill:SetStatusBarTexture(KE:GetStatusbarPath(self.db and self.db.StatusBarTexture or "KitnUI"))
            row.fill:SetMinMaxValues(0, tMax)
            row.fill:SetValue(t.total)
            row.fill:SetStatusBarColor(0.55, 0.20, 0.20)
            row.label:SetTextColor(1, 1, 1)
            row.value:SetTextColor(1, 1, 1)
            row.dps:SetTextColor(1, 1, 1)
            row.pct:SetTextColor(1, 1, 1)
            row.label:SetText(t.name)
            -- Amount + DPS via FormatBarValue (AbbreviateNumbers, secret-safe); both are plain
            -- accumulations from BuildAllPlayerTargets. % is the enemy-share (nil when unknown).
            row.value:SetText((self.FormatBarValue and select(1, self.FormatBarValue(t.total, nil, false))) or "")
            row.dps:SetText((self.FormatBarValue and select(1, self.FormatBarValue(t.dps or 0, nil, false))) or "")
            row.pct:SetText(t.pct and format("%.1f%%", t.pct) or "")
            row:Show()
            shownTargets = shownTargets + 1
        else
            row:Hide()
        end
    end

    if shownTargets == 0 then
        HideTipTargets()
        return 0
    end
    -- Gap + divider(1) + label band + the target rows.
    return TIP_TGT_GAP + 1 + TIP_TGT_LABEL_H + shownTargets * stride
end

-- Fill the tip from a bar's stashed source identity (set by RenderBar, Task 2).
-- Returns true if it has content to show, false if it should stay hidden. Mirrors
-- the secret contract of RenderBreakdown / RenderDeathRecap exactly. OOC ONLY for
-- real data: in combat it shows the secret message and reads NOTHING secret.
function DM:PopulateHoverTip(W, bar)
    self:EnsureHoverTip()
    local face = self.db and self.db.FontFace
    local size = self.db and self.db.FontSize
    local outline = self.db and self.db.FontOutline
    local headerH = TIP_PAD * 2 + (size or 12)

    -- IN COMBAT: hover fires mid-fight, so this gate is mandatory and runs BEFORE
    -- any secret read. bar._cachedName is the last PLAIN (non-secret) name RenderBar
    -- set (nil while the name was secret) -- safe to display, never a secret string.
    if InCombatLockdown() then
        for i = 1, HOVER_TIP_ROWS do _tip.rows[i].row:Hide() end
        if _tip.colHdr then
            _tip.colHdr.spell:Hide(); _tip.colHdr.amount:Hide(); _tip.colHdr.dps:Hide(); _tip.colHdr.pct:Hide()
        end
        HideTipTargets()
        _tip.header:SetText(bar._cachedName or "Details")
        -- Class-tint the title (bar._classFilename is NeverSecret). White fallback for
        -- an unknown/enemy class so the centered title is always legible.
        local chc = bar._classFilename and RAID_CLASS_COLORS[bar._classFilename]
        if chc then _tip.header:SetTextColor(chc.r, chc.g, chc.b) else _tip.header:SetTextColor(1, 1, 1) end
        _tip.msg:SetText("Detailed information is\nsecret while in combat")
        _tip.msg:Show()
        -- header + the two-line gray message; generous fixed height (no row math).
        _tip:SetHeight(headerH + TIP_PAD + (size or 12) * 3)
        return true
    end
    _tip.msg:Hide()

    local cfg = self:ResolveWindowConfig(W.idx)
    if not cfg then return false end
    local isDeaths = (cfg.MeterType == Enum.DamageMeterType.Deaths)

    -- Tip rows run ~2px shorter than the configured bar height so the quick-peek packs
    -- the now-15 rows (+ Targets) densely, closer to a full Details panel (request 2026-06-05).
    -- Clamped to a sane floor; stride keeps the configured inter-row spacing.
    local barH = math_max(8, (W._snapHeight or 16) - 2)
    local stride = barH + (W._snapSpacing or 2)
    local shown = 0
    local headerText = bar._cachedName or "Details"

    -- Phase 4c: the column-header row (Spell · Amount · DPS · %) is shown only for the
    -- breakdown path; the Deaths recap keeps its single value column. bodyTop pushes the
    -- data rows down past the column header in the breakdown path (0 for recap).
    local bodyTop = 0
    -- Phase 4c Targets sub-section extra height (0 unless a DamageDone breakdown renders it).
    local tgtExtraH = 0

    if isDeaths then
        -- Recap path: no column header, no Targets sub-section; data rows start right
        -- under the source header.
        if _tip.colHdr then
            _tip.colHdr.spell:Hide(); _tip.colHdr.amount:Hide(); _tip.colHdr.dps:Hide(); _tip.colHdr.pct:Hide()
        end
        HideTipTargets()
        -- Top recap events (oldest-first) for this death; nil -> nothing to show.
        local events, maxHP = self:GetDeathRecap(bar._deathRecapID)
        if not events then return false end
        local deathTime = events[#events] and events[#events].timestamp
        local count = math_min(#events, HOVER_TIP_ROWS)
        for i = 1, HOVER_TIP_ROWS do
            local tr = _tip.rows[i]
            local row = tr.row
            if i <= count then
                local ev = events[i]
                row:ClearAllPoints()
                local yOff = -(headerH + bodyTop + (i - 1) * stride)
                row:SetPoint("TOPLEFT", _tip, "TOPLEFT", TIP_PAD, yOff)
                row:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", -TIP_PAD, yOff)
                row:SetHeight(barH)

                -- Icon: spellId (lowercase d on recap events); pcall the lookup so a
                -- throw can't abort the loop. nil/0/error -> melee fallback 135274.
                local spID = ev.spellId
                local tex = 135274
                if spID and spID > 0 and C_Spell and C_Spell.GetSpellTexture then
                    local okT, t = pcall(C_Spell.GetSpellTexture, spID)
                    if okT and t then tex = t end
                end
                row.icon:SetTexture(tex)
                KE:ApplyIconZoom(row.icon)
                row.iconFrame:SetSize(barH, barH)
                row.iconFrame:Show()
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row.iconFrame, "RIGHT", 3, 0)
                -- Recap value is verbose ("-75.0K (overkill) (53%)") and uses the FULL right
                -- edge (no Amount/DPS/% columns); per-path anchor below pins row.value to
                -- -TIP_PAD. The label's RIGHT stops at row.value:LEFT so a long
                -- "(Source)" suffix ellipsizes exactly like Details rather than overlapping.
                row.value:ClearAllPoints()
                row.value:SetPoint("RIGHT", row.fill, "RIGHT", -TIP_PAD, 0)
                row.label:SetPoint("RIGHT", row.value, "LEFT", -3, 0)

                local evType = ev.event or ""
                local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
                local isFatal = (i == count and not isHeal)

                -- Fill = HP% remaining at the event; heal green / damage red.
                -- ev.currentHP is AllowedWhenUntainted like ev.amount -> sanitize to a plain
                -- number before the division (could be secret in a tainted post-combat window).
                local curHP = ev.currentHP
                if issecretvalue(curHP) or type(curHP) ~= "number" then curHP = 0 end
                local hpPct = math_min(1, math_max(0, maxHP > 0 and (curHP / maxHP) or 0))
                row.fill:SetMinMaxValues(0, 1)
                row.fill:SetValue(hpPct)
                if isHeal then row.fill:SetStatusBarColor(0.10, 0.50, 0.10)
                else row.fill:SetStatusBarColor(0.60, 0.08, 0.08) end

                -- Label: "-X.Xs SpellName (Source)" to match Details. Secret-guard the
                -- spellName return; append the event's source in parens when a plain
                -- (non-secret) sourceName exists and it isn't a heal (gray, ellipsizes).
                local spellName = ev.spellName
                if not spellName or issecretvalue(spellName) or spellName == "" then
                    if isHeal then spellName = "Heal"
                    elseif evType == "SWING_DAMAGE" then spellName = "Melee"
                    else spellName = "Unknown" end
                end
                local label = self.FormatRecapDelta(deathTime, ev.timestamp) .. " " .. spellName
                local sn = ev.sourceName
                if sn and not issecretvalue(sn) and sn ~= "" and not isHeal then
                    label = label .. "  |cff999999(" .. sn .. ")|r"
                end
                row.label:SetText(label)

                -- Value: +heal / -damage (AbbreviateNumbers via FormatBarValue), crit marker,
                -- killing-blow overkill, HP% suffix -- the exact secret-safe pattern as the
                -- click-inline RenderDeathRecap. Sanitize amount to a plain number before any
                -- math/tostring (GetRecapEvents is AllowedWhenUntainted -> could be secret in a
                -- tainted post-combat window); crit/overkill guarded as RenderDeathRecap.
                local amt = ev.amount or 0
                local amtPlain = amt
                if issecretvalue(amt) or type(amt) ~= "number" then amtPlain = 0 end
                local body = (self.FormatBarValue and select(1, self.FormatBarValue(math_max(0, amtPlain), nil, false))) or tostring(amtPlain)
                local sign = isHeal and "+" or "-"
                local critFlag = (not issecretvalue(ev.critical)) and ev.critical or false
                local crit = critFlag and " |cffffd100*|r" or ""
                local pctSuffix = format(" (%.0f%%)", hpPct * 100)
                if isFatal and not issecretvalue(ev.overkill) and type(ev.overkill) == "number" and ev.overkill > 0 then
                    local okStr = (self.FormatBarValue and select(1, self.FormatBarValue(ev.overkill, nil, false))) or tostring(ev.overkill)
                    row.value:SetText(sign .. body .. crit .. " |cffff3333(" .. okStr .. " overkill)|r" .. pctSuffix)
                else
                    row.value:SetText(sign .. body .. crit .. pctSuffix)
                end
                -- Recap keeps a single value column: the breakdown's DPS/% columns are empty.
                if row.dps then row.dps:SetText("") end
                if row.pct then row.pct:SetText("") end

                if not row:IsShown() then row:Show() end
                shown = shown + 1
            else
                if row:IsShown() then row:Hide() end
            end
        end
    else
        -- Top breakdown spells for this source (honor a pinned historical session).
        local src = self:GetSource(cfg.SessionType, cfg.MeterType, bar._sourceGUID, bar._sourceCreatureID, W._curSessionID)
        local spells = src and src.combatSpells
        if not spells then return false end

        -- Breakdown path: show the column-header row and push the data rows down past it.
        -- Reserve scales with the now-larger (size-1) white headers so big fonts can't overlap row 1.
        bodyTop = math_max(TIP_COL_HDR_H, (size or 12) + 2)
        if _tip.colHdr then
            local hdrY = -(headerH)
            _tip.colHdr.spell:ClearAllPoints()
            _tip.colHdr.spell:SetPoint("TOPLEFT", _tip, "TOPLEFT", TIP_PAD, hdrY)
            _tip.colHdr.amount:ClearAllPoints()
            _tip.colHdr.amount:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", TIP_AMT_X, hdrY)
            -- Re-apply the Spell label's right-stop (ClearAllPoints above dropped the
            -- build-time TOPRIGHT) so it stays bounded by the Amount column's left edge.
            _tip.colHdr.spell:SetPoint("TOPRIGHT", _tip.colHdr.amount, "TOPLEFT", -3, 0)
            _tip.colHdr.dps:ClearAllPoints()
            _tip.colHdr.dps:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", TIP_DPS_X, hdrY)
            _tip.colHdr.pct:ClearAllPoints()
            _tip.colHdr.pct:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", TIP_PCT_X, hdrY)
            _tip.colHdr.spell:Show(); _tip.colHdr.amount:Show(); _tip.colHdr.dps:Show(); _tip.colHdr.pct:Show()
        end

        local classColor = bar._classFilename and RAID_CLASS_COLORS[bar._classFilename]
        local maxAmount = src.maxAmount
        local canPercent = maxAmount and (not issecretvalue(maxAmount)) and type(maxAmount) == "number"
            and src.totalAmount and not issecretvalue(src.totalAmount)
        local total = canPercent and src.totalAmount or 0
        local count = math_min(#spells, HOVER_TIP_ROWS)

        for i = 1, HOVER_TIP_ROWS do
            local tr = _tip.rows[i]
            local row = tr.row
            if i <= count then
                local spell = spells[i]
                row:ClearAllPoints()
                local yOff = -(headerH + bodyTop + (i - 1) * stride)
                row:SetPoint("TOPLEFT", _tip, "TOPLEFT", TIP_PAD, yOff)
                row:SetPoint("TOPRIGHT", _tip, "TOPRIGHT", -TIP_PAD, yOff)
                row:SetHeight(barH)

                -- Icon from spellID (safe OOC). pcall the lookup; failure -> hidden icon.
                local iconShown = false
                local spID = spell.spellID
                if spID and C_Spell and C_Spell.GetSpellTexture then
                    local okT, tex = pcall(C_Spell.GetSpellTexture, spID)
                    if okT and tex then
                        row.icon:SetTexture(tex)
                        KE:ApplyIconZoom(row.icon)
                        row.iconFrame:SetSize(barH, barH)
                        row.iconFrame:Show()
                        iconShown = true
                    end
                end
                if not iconShown then row.iconFrame:Hide() end

                -- Per-path column anchors. The row pool is shared with the recap branch,
                -- which re-anchors row.value to the full right edge (-TIP_PAD); re-pin the
                -- three numeric columns to their fixed offsets here so a breakdown render
                -- after a recap render restores the aligned-column layout.
                row.value:ClearAllPoints()
                row.value:SetPoint("RIGHT", row.fill, "RIGHT", TIP_AMT_X, 0)
                row.dps:ClearAllPoints()
                row.dps:SetPoint("RIGHT", row.fill, "RIGHT", TIP_DPS_X, 0)
                row.pct:ClearAllPoints()
                row.pct:SetPoint("RIGHT", row.fill, "RIGHT", TIP_PCT_X, 0)

                row.label:ClearAllPoints()
                if iconShown then
                    row.label:SetPoint("LEFT", row.iconFrame, "RIGHT", 3, 0)
                else
                    row.label:SetPoint("LEFT", row.fill, "LEFT", 3, 0)
                end
                row.label:SetPoint("RIGHT", row.value, "LEFT", -3, 0)

                -- Sanitize the per-spell amount before any Lua math/format (parity
                -- with RenderBreakdown); raw amount still feeds SetValue.
                local amt = spell.totalAmount
                local amtPlain = amt
                if issecretvalue(amt) or type(amt) ~= "number" then amtPlain = 0 end

                row.fill:SetMinMaxValues(0, maxAmount or 1)
                row.fill:SetValue(amt or 0)
                if classColor then
                    row.fill:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
                else
                    local ar, ag, ab = KE:GetAccentColor()
                    row.fill:SetStatusBarColor(ar or 0.6, ag or 0.6, ab or 0.6)
                end

                local nm
                if spID then
                    local ok, sn = pcall(C_Spell.GetSpellName, spID)
                    if ok and sn and not issecretvalue(sn) then nm = sn end
                end
                row.label:SetText(nm or spell.creatureName or "Unknown")

                -- Phase 4c columns: Amount, DPS, %. Each fed only by FormatBarValue
                -- (AbbreviateNumbers, secret-safe) or %.1f on a sanitized plain number.
                -- Amount column.
                local amtStr = (self.FormatBarValue and select(1, self.FormatBarValue(amtPlain, nil, false))) or ""
                row.value:SetText(amtStr)

                -- DPS column: per-second value from spell.amountPerSecond, sanitized to a
                -- plain number exactly like amtPlain before FormatBarValue (which itself is
                -- AllowedWhenTainted / secret-safe). No bare math on the raw value.
                local ps = spell.amountPerSecond
                if issecretvalue(ps) or type(ps) ~= "number" then ps = 0 end
                local dpsStr = (self.FormatBarValue and select(1, self.FormatBarValue(ps, nil, false))) or ""
                row.dps:SetText(dpsStr)

                -- % column: share of this source's total (gated on canPercent; arithmetic
                -- runs on the sanitized amtPlain / guarded total only).
                if canPercent and total > 0 then
                    row.pct:SetText(format("%.1f%%", (amtPlain / total) * 100))
                else
                    row.pct:SetText("")
                end

                if not row:IsShown() then row:Show() end
                shown = shown + 1
            else
                if row:IsShown() then row:Hide() end
            end
        end

        -- Targets sub-section: DamageDone only. Renders below the spell rows; returns the
        -- extra height it consumed (0 / hides itself when there are no targets). For any
        -- other breakdown meter type (HealingDone, etc.) the section stays hidden.
        if shown > 0 and cfg.MeterType == Enum.DamageMeterType.DamageDone then
            local topY = -(headerH + bodyTop + shown * stride)
            tgtExtraH = RenderTipTargets(self, bar, cfg, W._curSessionID, topY, stride, barH)
        else
            HideTipTargets()
        end
    end

    if shown == 0 then HideTipTargets(); return false end
    _tip.header:SetText(headerText)
    -- Class-tint the centered title from the NeverSecret class filename (white fallback).
    local hdrClass = bar._classFilename and RAID_CLASS_COLORS[bar._classFilename]
    if hdrClass then _tip.header:SetTextColor(hdrClass.r, hdrClass.g, hdrClass.b) else _tip.header:SetTextColor(1, 1, 1) end
    -- Re-apply the live font in case a GUI change happened (ReapplyBarVisuals also
    -- handles this, but a hover before the first reapply still wants current fonts).
    KE:ApplyFontToText(_tip.header, face, size, outline)
    -- bodyTop reserves the column-header band (breakdown path; 0 for the recap path);
    -- tgtExtraH reserves the Targets sub-section (DamageDone breakdown only, else 0).
    _tip:SetHeight(headerH + bodyTop + TIP_PAD + shown * stride + tgtExtraH)
    return true
end

-- Show the tip for a hovered bar. Suppressed when the click-inline panel is open,
-- when disabled via DB, or for an empty/placeholder row. On success it pins the
-- active bar + starts the live poll; otherwise it hides.
-- isInitial: true only from the OnEnter handler. The anchor (ClearAllPoints/SetPoint)
-- is set ONCE on initial hover -- bar.row is stationary and HoverTooltipAnchor only
-- changes via the GUI, so the 4 Hz poll (isInitial nil/false) skips the anchor block
-- to avoid spurious layout invalidation for the whole hover duration.
function DM:ShowHoverTip(W, bar, isInitial)
    if not W or not bar then return end
    if self.db and self.db.HoverTooltip == false then return end       -- DB toggle (Task 10)
    if W._detailOpen then return end                                    -- click-inline open: suppress
    if not (bar._sourceGUID or bar._sourceCreatureID or bar._deathRecapID) then return end  -- empty/placeholder row

    if self:PopulateHoverTip(W, bar) then
        if isInitial then
            -- Phase 4c smart positioning. Modes: smart | bar | left | right | center.
            -- "smart" places the tip on the meter's OPEN side (away from the nearer screen
            -- edge), re-evaluated each initial hover so a moved/redocked meter picks the
            -- right side next time. SetClampedToScreen (set in EnsureHoverTip) is the
            -- backstop. left/right anchor to W.frame; bar anchors above the hovered bar.
            local mode = (self.db and self.db.HoverTooltipAnchor) or "smart"
            _tip:ClearAllPoints()
            if mode == "center" then
                _tip:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            elseif mode == "bar" then
                _tip:SetPoint("BOTTOMLEFT", bar.row, "TOPLEFT", 0, 2)
            else
                local side = mode
                if mode == "smart" then
                    local cx = (W.frame:GetLeft() or 0) + (W.frame:GetWidth() or 0) / 2
                    side = (cx > (UIParent:GetWidth() or 0) / 2) and "left" or "right"
                end
                if side == "left" then
                    _tip:SetPoint("TOPRIGHT", W.frame, "TOPLEFT", -4, 0)
                else
                    _tip:SetPoint("TOPLEFT", W.frame, "TOPRIGHT", 4, 0)
                end
            end
        end
        _tip:Show()
        _tipActiveBar = bar
        if _tipPoll then _tipPollAccum = 0; _tipPoll:Show() end
    else
        self:HideHoverTip()
    end
end

-- Hide the tip + stop the poll. Cheap; safe to call when nothing is shown.
function DM:HideHoverTip()
    _tipActiveBar = nil
    if _tipPoll then _tipPoll:Hide() end
    if _tip then _tip:Hide() end
end

-- Re-apply font + statusbar texture to the shared tip after a live GUI font/texture
-- change (called from ReapplyBarVisuals). No-op until the tip has been built. The tip
-- is a module-level singleton, so this is window-agnostic -- ReapplyBarVisuals runs
-- per window, but the tip only needs one pass; the redundant calls are cheap setters.
function DM:ReapplyHoverTipVisuals()
    if not _tip then return end
    local db = self.db
    local face = db and db.FontFace
    local size = db and db.FontSize
    local outline = db and db.FontOutline
    local texPath = KE:GetStatusbarPath(db and db.StatusBarTexture or "KitnUI")

    KE:ApplyFontToText(_tip.header, face, size, outline)
    if _tip.msg then KE:ApplyFontToText(_tip.msg, face, size, outline) end
    -- Phase 4c: the column-header labels track the data font (white, one notch below data).
    if _tip.colHdr then
        local colSize = math.max(9, (size or 12) - 1)
        KE:ApplyFontToText(_tip.colHdr.spell, face, colSize, outline)
        KE:ApplyFontToText(_tip.colHdr.amount, face, colSize, outline)
        KE:ApplyFontToText(_tip.colHdr.dps, face, colSize, outline)
        KE:ApplyFontToText(_tip.colHdr.pct, face, colSize, outline)
    end
    if _tip.rows then
        for i = 1, HOVER_TIP_ROWS do
            local tr = _tip.rows[i]
            if tr and tr.row then
                tr.row.fill:SetStatusBarTexture(texPath)
                KE:ApplyFontToText(tr.row.label, face, size, outline)
                KE:ApplyFontToText(tr.row.value, face, size, outline)
                -- Phase 4c numeric columns (DPS / %).
                if tr.row.dps then KE:ApplyFontToText(tr.row.dps, face, size, outline) end
                if tr.row.pct then KE:ApplyFontToText(tr.row.pct, face, size, outline) end
            end
        end
    end
    -- Phase 4c Targets sub-section: label tracks the data font at the small size; rows
    -- track the data font + statusbar texture. Lazy-built, so guard on existence.
    if _tip.tgtLabel then
        local lblSize = math.max(9, (size or 12) - 1)   -- match the white column headers
        KE:ApplyFontToText(_tip.tgtLabel, face, lblSize, outline)
        if _tip.tgtHdrAmount then
            KE:ApplyFontToText(_tip.tgtHdrAmount, face, lblSize, outline)
            KE:ApplyFontToText(_tip.tgtHdrDps, face, lblSize, outline)
            KE:ApplyFontToText(_tip.tgtHdrPct, face, lblSize, outline)
        end
    end
    if _tip.tgtRows then
        for ti = 1, TIP_TGT_ROWS do
            local tr = _tip.tgtRows[ti]
            if tr and tr.row then
                tr.row.fill:SetStatusBarTexture(texPath)
                KE:ApplyFontToText(tr.row.label, face, size, outline)
                KE:ApplyFontToText(tr.row.value, face, size, outline)
                if tr.row.dps then KE:ApplyFontToText(tr.row.dps, face, size, outline) end
                if tr.row.pct then KE:ApplyFontToText(tr.row.pct, face, size, outline) end
            end
        end
    end

    -- Re-sync the backdrop to the live DB color. The GUI backdrop callback replaces
    -- db.BackdropColor / db.BackdropBorderColor with fresh tables, so _backdropCfg's
    -- by-reference copies go stale; re-point them and re-apply so the tip chrome
    -- tracks GUI color changes without a /reload.
    if _tip._backdropCfg then
        _tip._backdropCfg.Color = (db and db.BackdropColor) or { 0.031, 0.031, 0.031, 0.95 }
        _tip._backdropCfg.BorderColor = (db and db.BackdropBorderColor) or { 0, 0, 0, 1 }
        KE:ApplyBackdrop(_tip, _tip._backdropCfg)
    end
end

-- Detach-when-idle live poll (KE OnUpdate detach-when-idle pattern). Only runs while
-- a bar is actively hovered; re-populates ~4 Hz so settling numbers stay live (OOC)
-- or the combat message stays put. Hides itself the instant the active bar is gone.
_tipPoll = CreateFrame("Frame")
_tipPoll:Hide()
_tipPoll:SetScript("OnUpdate", function(self, elapsed)
    _tipPollAccum = _tipPollAccum + elapsed
    if _tipPollAccum < 0.25 then return end   -- ~4 Hz refresh is plenty for a hover peek
    _tipPollAccum = 0
    local bar = _tipActiveBar
    if not bar or not bar.win then self:Hide(); return end
    DM:ShowHoverTip(bar.win, bar, false)      -- re-populate live (OOC) / keep the combat message; skip re-anchor
end)

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
local issecretvalue = issecretvalue
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local math_min, math_max = math.min, math.max
local format = string.format

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
            local curHP = ev.currentHP or 0
            local hpPct = math_min(1, math_max(0, maxHP > 0 and (curHP / maxHP) or 0))
            row.fill:SetMinMaxValues(0, 1)
            row.fill:SetValue(hpPct)
            if isHeal then row.fill:SetStatusBarColor(0.10, 0.50, 0.10)
            else row.fill:SetStatusBarColor(0.60, 0.08, 0.08) end

            -- Label: "-X.Xs SpellName" (+ " from Source" when a non-secret sourceName exists).
            local spellName = ev.spellName
            if not spellName or issecretvalue(spellName) or spellName == "" then
                if isHeal then spellName = "Heal"
                elseif evType == "SWING_DAMAGE" then spellName = "Melee"
                else spellName = "Unknown" end
            end
            local label = self.FormatRecapDelta(deathTime, ev.timestamp) .. " " .. spellName
            local srcName = ev.sourceName
            if srcName and not issecretvalue(srcName) and srcName ~= "" and not isHeal then
                label = label .. " |cff999999from " .. srcName .. "|r"
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

local HOVER_TIP_ROWS = 8        -- quick-peek shows the top few; the click-inline panel shows the full list
local TIP_WIDTH = 220
local TIP_PAD = 4               -- inner inset for header / rows
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
    row.value = row.fill:CreateFontString(nil, "OVERLAY")
    row.value:SetPoint("RIGHT", row.fill, "RIGHT", -3, 0)
    row.value:SetJustifyH("RIGHT")
    KE:ApplyFontToText(row.value, face, size, outline)

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

    f.header = f:CreateFontString(nil, "OVERLAY")
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", TIP_PAD, -TIP_PAD)
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -TIP_PAD, -TIP_PAD)
    f.header:SetJustifyH("LEFT")
    f.header:SetWordWrap(false)
    KE:ApplyFontToText(f.header, face, size, outline)

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
        _tip.header:SetText(bar._cachedName or "Details")
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

    local stride = (W._snapStride or 18)
    local barH = (W._snapHeight or 16)
    local shown = 0
    local headerText = bar._cachedName or "Details"

    if isDeaths then
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
                local yOff = -(headerH + (i - 1) * stride)
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
                row.label:SetPoint("RIGHT", row.value, "LEFT", -3, 0)

                local evType = ev.event or ""
                local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")

                -- Fill = HP% remaining at the event; heal green / damage red.
                local curHP = ev.currentHP or 0
                local hpPct = math_min(1, math_max(0, maxHP > 0 and (curHP / maxHP) or 0))
                row.fill:SetMinMaxValues(0, 1)
                row.fill:SetValue(hpPct)
                if isHeal then row.fill:SetStatusBarColor(0.10, 0.50, 0.10)
                else row.fill:SetStatusBarColor(0.60, 0.08, 0.08) end

                -- Label: "-X.Xs SpellName" (secret-guard the spellName return).
                local spellName = ev.spellName
                if not spellName or issecretvalue(spellName) or spellName == "" then
                    if isHeal then spellName = "Heal"
                    elseif evType == "SWING_DAMAGE" then spellName = "Melee"
                    else spellName = "Unknown" end
                end
                row.label:SetText(self.FormatRecapDelta(deathTime, ev.timestamp) .. " " .. spellName)

                -- Value: +heal / -damage. Sanitize amount to a plain number before any
                -- math/tostring (GetRecapEvents is AllowedWhenUntainted -> could be
                -- secret in a tainted post-combat window); crit guarded as RenderDeathRecap.
                local amt = ev.amount or 0
                local amtPlain = amt
                if issecretvalue(amt) or type(amt) ~= "number" then amtPlain = 0 end
                local body = (self.FormatBarValue and select(1, self.FormatBarValue(math_max(0, amtPlain), nil, false))) or tostring(amtPlain)
                local critFlag = (not issecretvalue(ev.critical)) and ev.critical or false
                local crit = critFlag and " |cffffd100*|r" or ""
                row.value:SetText((isHeal and "+" or "-") .. body .. crit)

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
                local yOff = -(headerH + (i - 1) * stride)
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

                local amtStr = (self.FormatBarValue and select(1, self.FormatBarValue(amtPlain, nil, false))) or ""
                if canPercent and total > 0 then
                    row.value:SetText(format("%s  %.1f%%", amtStr, (amtPlain / total) * 100))
                else
                    row.value:SetText(amtStr)
                end

                if not row:IsShown() then row:Show() end
                shown = shown + 1
            else
                if row:IsShown() then row:Hide() end
            end
        end
    end

    if shown == 0 then return false end
    _tip.header:SetText(headerText)
    -- Re-apply the live font in case a GUI change happened (ReapplyBarVisuals also
    -- handles this, but a hover before the first reapply still wants current fonts).
    KE:ApplyFontToText(_tip.header, face, size, outline)
    _tip:SetHeight(headerH + TIP_PAD + shown * stride)
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
            _tip:ClearAllPoints()
            if self.db and self.db.HoverTooltipAnchor == "center" then
                _tip:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            else
                _tip:SetPoint("BOTTOMLEFT", bar.row, "TOPLEFT", 0, 2)
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
    if _tip.rows then
        for i = 1, HOVER_TIP_ROWS do
            local tr = _tip.rows[i]
            if tr and tr.row then
                tr.row.fill:SetStatusBarTexture(texPath)
                KE:ApplyFontToText(tr.row.label, face, size, outline)
                KE:ApplyFontToText(tr.row.value, face, size, outline)
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

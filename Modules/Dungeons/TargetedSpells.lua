-- ╔══════════════════════════════════════════════════════════╗
-- ║  TargetedSpells.lua                                      ║
-- ║  Module: Targeted Spells                                 ║
-- ║  Purpose: Mirrored icon/countdown entries for enemy      ║
-- ║           nameplate casts that target the player.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class TargetedSpells: AceModule, AceEvent-3.0
local TS = KitnEssentials:NewModule("TargetedSpells", "AceEvent-3.0")

local CreateFrame = CreateFrame
local IsInInstance, GetInstanceInfo = IsInInstance, GetInstanceInfo
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitCastingDuration, UnitChannelDuration = UnitCastingDuration, UnitChannelDuration
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration
local PlayerIsSpellTarget = PlayerIsSpellTarget
local C_Spell = C_Spell
local GetTime = GetTime
local C_Timer = C_Timer
local C_StringUtil = C_StringUtil
local tinsert, tremove, tsort = table.insert, table.remove, table.sort
local tconcat = table.concat
local UnitAffectingCombat, UnitExists = UnitAffectingCombat, UnitExists
local UnitCanAttack = UnitCanAttack
local type, ipairs = type, ipairs

-- Size-parameterized pixel glow fork (TargetedSpellsGlow.lua, loads first);
-- nil in headless specs, so glow paths gate on it.
local Glows = KE.TSGlow

local issecretvalue = issecretvalue

local DEBUG_TS = false
-- KE:Print renders only its first argument — concat everything into one
-- string. tostring(secret) SUCCEEDS and returns a secret string (concat
-- then throws), so the guard must be issecretvalue, not pcall.
local function describeValue(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return tostring(v)
end
local function dbg(...)
    if not DEBUG_TS then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = describeValue((select(i, ...)))
    end
    KE:Print("|cff88ccff[TS]|r " .. table.concat(parts, " "))
end

-- Delve difficultyID — probe-confirmed in-game (Collegiate
-- Calamity delve: instanceType "scenario", difficultyID 208).
TS.DELVE_DIFFICULTY_ID = 208

local FALLBACK_ICON = 136243
-- GUI close-button cross (GUI-MainFrame.lua idiom: rotate 45° into an X).
local INTERRUPT_ICON = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png"
-- RegisterUnitEvent takes at most this many unit tokens per call, so the
-- nameplate range is covered by one shard frame per slice. The guard is not
-- decoration: Constants does not exist in the headless spec environment, and an
-- unguarded read here throws at module load.
local UNITS_PER_SHARD = (Constants and Constants.UnitEventConstants
    and Constants.UnitEventConstants.MAX_UNIT_TOKENS_IN_EVENT) or 4
-- The full documented nameplate token range. Sharding a shorter range silently
-- drops casts from units the module shows today: the previous cap bounded only
-- the rescan loop, while event delivery was unfiltered and accepted any index.
local MAX_NAMEPLATE_TOKENS = 150
local SETTLE_DELAY = 0.2
local INTERRUPT_LINGER = 1.0   -- seconds the desaturated icon stays up post-interrupt
local INTERRUPT_HOLD = 0.95    -- Release() suppression window; < LINGER avoids a same-tick race with the linger timer
local PREVIEW_ENTRY_COUNT = 2   -- entries the edit-mode preview draws; see PREVIEW_ENTRIES

-- Breakpoint countdown formatter: db.Decimals digits for the whole sub-60
-- range, m:ss above (only reachable if the >60s gate changes). The
-- format string is plain — the widget does the secret-side formatting.
-- Lazy so headless spec loads (no C_StringUtil in busted) never touch it;
-- cache is keyed on the decimals value so the GUI slider rebuilds it.
local castFormatter, castFormatterDecimals
local function GetCastFormatter(decimals)
    decimals = decimals or 1
    if castFormatter and castFormatterDecimals ~= decimals then
        castFormatter = nil
    end
    if not castFormatter and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
        castFormatter = C_StringUtil.CreateNumericRuleFormatter()
        castFormatter:SetBreakpoints({
            { threshold = 0, format = "%." .. decimals .. "f" },
            { threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } },
        })
        castFormatterDecimals = decimals
    end
    return castFormatter
end

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

TS.entryPool = {}
TS.activeEntries = {}   -- unit -> entry
TS.activeCount = 0
TS.contentActive = false
TS.isPreview = false
-- unit -> plain counter, bumped on every delayed-start dispatch. TryStart
-- aborts unless its token still matches, coalescing stale/superseded
-- dispatches without comparing any secret cast id (see BumpDispatchToken).
TS.pendingDispatch = {}
TS.UNITS_PER_SHARD = UNITS_PER_SHARD
TS.MAX_NAMEPLATE_TOKENS = MAX_NAMEPLATE_TOKENS
-- Cast and target events arrive here instead of on AceEvent, which has no
-- unit-filtered registration: a plain RegisterEvent wakes this module for every
-- casting unit in the world, including every party member's global cooldown,
-- only to fail a nameplate test.
TS.shards = {}
-- Delayed cast starts as a FIFO. SETTLE_DELAY is constant, so arrival order is
-- due order and nothing needs sorting. One scheduled drain covers the queue.
TS.pendingCasts = {}
TS.pendingHead = 1
TS.pendingTail = 0
TS.drainScheduled = false
-- C_Timer.After cannot be cancelled, so a drain scheduled before the queue was
-- discarded still runs. It compares this on entry and returns if stale.
TS.drainEpoch = 0
-- Reused by RepositionEntries. Never escapes that function.
TS.sortScratch = {}
-- Resolved once per rebuild rather than per cast. Both are pure functions of
-- settings, and every settings change already drops the entry pool.
TS.cachedFontPath = nil
TS.cachedFontOutline = nil

---------------------------------------------------------------------------------
-- Pure helpers (busted-covered — keep WoW-API-free)
---------------------------------------------------------------------------------

-- Decides visibility from the five content checkboxes. Non-delve scenarios
-- follow the open-world flag.
function TS.ShouldShowForInstance(db, inInstance, instanceType, difficultyID)
    if not inInstance then
        return db.ShowInOpenWorld == true
    end
    if instanceType == "party" then return db.ShowInDungeons ~= false end
    if instanceType == "raid" then return db.ShowInRaids == true end
    if instanceType == "arena" or instanceType == "pvp" then return db.ShowInPvP == true end
    if instanceType == "scenario" then
        if difficultyID == TS.DELVE_DIFFICULTY_ID then return db.ShowInDelves ~= false end
        return db.ShowInOpenWorld == true
    end
    return db.ShowInOpenWorld == true
end

-- Sort key is the plain Lua receipt time (secret cast start times cannot be
-- compared); strict less-than keeps table.sort stable-safe.
function TS.CompareEntries(a, b)
    return (a.receiptTime or 0) < (b.receiptTime or 0)
end

-- Number of shard frames needed to cover maxTokens at perShard each.
function TS.ShardCount(perShard, maxTokens)
    return math.ceil(maxTokens / perShard)
end

-- Index of the first entry not yet due. Pure so ordering is testable without
-- C_Timer or GetTime.
function TS.FirstNotDue(pending, head, tail, now)
    local i = head
    while i <= tail and pending[i] and pending[i].dueAt <= now do
        i = i + 1
    end
    return i
end

-- The unit tokens one shard registers. Returns nil past the end of the range.
-- The final shard holds the remainder when the range does not divide evenly.
function TS.ShardTokens(shardIndex, perShard, maxTokens)
    local first = (shardIndex - 1) * perShard + 1
    if first > maxTokens then return nil end
    local last = math.min(first + perShard - 1, maxTokens)
    local tokens = {}
    for i = first, last do
        tokens[#tokens + 1] = "nameplate" .. i
    end
    return tokens
end

-- Every setting a pooled entry frame bakes in when it is built, as one
-- comparable value.
--
-- The set has a single definition, and it is not this function: it is whatever
-- the settings page routes through QueueRebuild. That is the module's own
-- statement of "the pooled frames are now stale", it already covers the layout
-- sliders, the whole font card and the countdown colour, and keeping this in
-- step with it is the only rule needed. A term the page rebuilds for but this
-- omits is a setting that silently stops rebuilding.
--
-- It matters because ApplySettings is the in-place path — glow and content
-- gating — and is also what a profile switch reaches. Without this comparison
-- the pooled frames keep the previous profile's geometry.
-- No fallbacks for the settings themselves. A fallback here would have to guess
-- which of the module's own defaults the builders would land on, and guessing
-- wrong turns a real change into no change. tostring keeps a nil comparable
-- instead, so an absent setting differs from a present one.
--
-- The two font terms are the exception, and neither is a fallback. Both are
-- stored values that stand for something else at render time, so keying them
-- raw is wrong in both directions — settings that render identically key
-- differently and rebuild on every switch, and settings that render differently
-- can key the same. A stored face name is resolved through the global font, a
-- media lookup and a fallback before anything is drawn with it; several stored
-- outline values collapse onto the same rendered outline. Both reach the key
-- already resolved, by the same two calls the entry builder makes.
--
-- Absent values are keyed fail-closed. The builders carry their own `or`
-- fallbacks, so an absent term does render as something — but keying that
-- guess would let a real change read as no change, while keying the absence
-- only costs one extra rebuild. Over-rebuilding is visible and cheap;
-- under-rebuilding is silent and wrong.
local REBUILD_KEY_FIELDS = {
    "IconSize", "TextSpacing", "Gap", "Grow", "MaxIcons",
    "FontSize", "Decimals",
}

---@param db table?
---@param fontPath string? resolved font FILE, not db.FontFace
---@param fontOutline string? resolved outline, not db.FontOutline
---@return string
function TS.RebuildKey(db, fontPath, fontOutline)
    if not db then return "" end

    local parts = {}
    for i = 1, #REBUILD_KEY_FIELDS do
        parts[i] = tostring(db[REBUILD_KEY_FIELDS[i]])
    end
    parts[#parts + 1] = tostring(fontPath)
    parts[#parts + 1] = tostring(fontOutline)

    local colour = db.FontColor
    for i = 1, 4 do
        parts[#parts + 1] = tostring(colour and colour[i])
    end

    return tconcat(parts, ":")
end

-- The key for the settings that are live right now. Kept separate from the pure
-- helper so the resolutions have one home and the helper stays comparable
-- against any font or outline a caller wants to ask about.
--
-- These are the same two calls the entry builder makes, verbatim. That is the
-- whole point: the FILE is what gets drawn with, and the name is several
-- lookups away from it — a stored name absent from the media library falls back
-- to the default font, so two names nobody registered render identically. Key
-- the file and the question "did the text change" is answered by the same value
-- that decided how it looked.
---@return string
function TS:CurrentRebuildKey()
    local db = self.db
    if not db then return TS.RebuildKey(nil) end
    return TS.RebuildKey(db,
        KE:GetFontPath(db.FontFace),
        KE:GetFontOutline(db.FontOutline))
end

-- Overlay insets for the entry stack. The anchor frame is one entry tall and
-- every entry chains off its outer edge, so nothing is ever drawn inside it:
-- the box has to be MOVED onto the stack, not merely grown over it. The
-- negative term is the anchor frame's own height, which cancels it out, and the
-- positive term is the stack span. Sized to what edit mode actually draws,
-- which is the preview set, not the MaxIcons cap.
---@param db table?
---@return number left, number right, number top, number bottom
function TS.PreviewStackInset(db)
    if not db then return 0, 0, 0, 0 end
    local size = db.IconSize or 36
    local n = PREVIEW_ENTRY_COUNT
    local span = n * size + (n - 1) * (db.Gap or 3)
    if (db.Grow or "DOWN") == "UP" then
        return 0, 0, span, -size
    end
    return 0, 0, -size, span
end

---------------------------------------------------------------------------------
-- DB / lifecycle
---------------------------------------------------------------------------------

function TS:UpdateDB()
    self.db = KE.db.profile.TargetedSpells
    -- One-time enable fixup: a profile that physically stored
    -- Enabled=false under the old default-off era (AceDB only strips
    -- default-equal values on a clean logout) would pin the module off
    -- forever now that the default is on. Runs once per profile; the flag
    -- then persists, so post-fixup disables stick.
    if not self.db.EnableFixup then
        self.db.EnableFixup = true
        self.db.Enabled = true
    end
end

function TS:OnInitialize()
    self:UpdateDB()
    -- Ace default module state is enabled; without this a db-disabled module
    -- still counts as IsEnabled() (first GUI enable becomes a no-op and core
    -- PEW ApplySettings runs the gate with no anchor frame). Sibling idiom:
    -- DungeonCasts.lua / KeystoneHelper.lua / FocusCastbar.lua /
    -- PlayerAbsorbs.lua — Core/Main.lua's OnEnable loop owns the actual
    -- enable decision via db.Enabled.
    self:SetEnabledState(false)
end

local SHARD_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_TARGET",
}
TS.SHARD_EVENTS = SHARD_EVENTS

-- AceEvent strips the receiver before calling its handlers, so the raw frame
-- callback adapts to the signatures the handlers already have.
local function ShardOnEvent(_, event, unit, ...)
    if event == "UNIT_TARGET" then
        TS:OnUnitTarget(nil, unit)
    else
        TS:OnCastEvent(event, unit, ...)
    end
end
TS.ShardOnEvent = ShardOnEvent

function TS:CreateShards()
    if #self.shards > 0 then return end
    for i = 1, TS.ShardCount(UNITS_PER_SHARD, MAX_NAMEPLATE_TOKENS) do
        local shard = CreateFrame("Frame")
        shard.tokens = TS.ShardTokens(i, UNITS_PER_SHARD, MAX_NAMEPLATE_TOKENS)
        shard:SetScript("OnEvent", ShardOnEvent)
        self.shards[i] = shard
    end
end

function TS:RegisterShardEvents()
    for _, shard in ipairs(self.shards) do
        for _, event in ipairs(SHARD_EVENTS) do
            shard:RegisterUnitEvent(event, unpack(shard.tokens))
        end
    end
end

function TS:UnregisterShardEvents()
    for _, shard in ipairs(self.shards) do
        shard:UnregisterAllEvents()
    end
end

function TS:OnEnable()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end

    -- Before SyncStructure, which reaches CheckContentGate: registering an
    -- empty shard list is a silent no-op that then marks the gate active, after
    -- which nothing registers again.
    self:CreateShards()
    self:CreateAnchorFrame()
    -- Before anything can acquire an entry. A re-enable under a different
    -- profile finds the pool still holding the previous profile's frames, and
    -- newly-enabled modules deliberately skip ApplySettings, so this is the
    -- only hook on that path.
    self:SyncStructure()
    self:ApplyPosition()
    -- OnDisable hides the anchor and nothing else re-Shows it (ApplyPosition
    -- doesn't); without this a GUI disable→re-enable leaves live entries
    -- parented to a hidden frame until a preview fires or /reload.
    self.anchorFrame:Show()

    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnNameplateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNameplateRemoved")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckContentGate")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CheckContentGate")

    self:CheckContentGate()
    self:RegisterEditMode()
    self:CheckCVarPrompt()   -- one-time nameplateShowOffscreen prompt
end

function TS:OnDisable()
    self:UnregisterShardEvents()
    self:DiscardPendingCasts()
    self:UnregisterAllEvents()
    self:ReleaseAllEntries()
    for _, entry in ipairs(self.entryPool) do
        self:ReleaseGlow(entry)
    end
    -- Nothing else clears this, and a stale true sends the next gate check down
    -- the already-active branch, which never registers: the module would come
    -- back enabled and permanently deaf.
    self.contentActive = false
    if self.anchorFrame then self.anchorFrame:Hide() end
end

---------------------------------------------------------------------------------
-- Content gating
---------------------------------------------------------------------------------

function TS:ShouldBeActive()
    if self.isPreview then return true end
    local inInstance, instanceType = IsInInstance()
    local _, _, difficultyID = GetInstanceInfo()
    return TS.ShouldShowForInstance(self.db, inInstance, instanceType, difficultyID)
end

function TS:CheckContentGate()
    -- PreviewManager calls HidePreview (-> CheckContentGate) unconditionally
    -- on section transitions even for db-disabled modules; the gate must
    -- never run while the module is disabled (anchorFrame may not exist).
    if not self:IsEnabled() then return end
    local shouldBeActive = self:ShouldBeActive()
    if shouldBeActive and not self.contentActive then
        self.contentActive = true
        dbg("gate ON")
        self:RegisterShardEvents()
        self:ScanExistingNameplates()
    elseif not shouldBeActive and self.contentActive then
        self.contentActive = false
        self:UnregisterShardEvents()
        self:DiscardPendingCasts()
        dbg("gate OFF")
        if not self.isPreview then
            self:ReleaseAllEntries()
        end
    elseif shouldBeActive then
        -- PLAYER_ENTERING_WORLD with the gate already on: rescan (a /reload
        -- mid-combat leaves in-flight casts that fire no new START events).
        self:ScanExistingNameplates()
    end
end

---------------------------------------------------------------------------------
-- Anchor frame / position / EditMode
---------------------------------------------------------------------------------

-- Entry/anchor width, single source of truth: two icons plus the middle
-- countdown slot (db.TextSpacing px, user-tunable in the Layout card).
local function EntryWidth(db)
    return db.IconSize * 2 + (db.TextSpacing or 32)
end

-- Creates the anchor, or re-sizes the one that already exists. A frame is never
-- destroyed, so a profile switch that re-enables this module reuses the previous
-- profile's anchor: re-sizing here is what stops it keeping the other profile's
-- dimensions. Callers must not guard this with `if not self.anchorFrame` — that
-- guard is what hid the mismatch. It deliberately does NOT stamp the rebuild
-- key: re-sizing the anchor says nothing about the pooled entry frames, and
-- claiming otherwise is how they end up stale.
function TS:CreateAnchorFrame()
    if not self.anchorFrame then
        self.anchorFrame = CreateFrame("Frame", "KE_TargetedSpells", UIParent)
    end
    self.anchorFrame:SetSize(EntryWidth(self.db), self.db.IconSize)
end

-- The one place that decides whether the pooled frames still match the profile.
-- Disabling this module only RELEASES its entries into the pool, so a re-enable
-- under a different profile finds frames built to the old numbers; and a switch
-- that leaves the module enabled reaches ApplySettings, which is the in-place
-- path. Both come through here.
--
-- Only RebuildEntries may stamp the key, because only RebuildEntries actually
-- drops the pool. Stamping anywhere else — after re-sizing the anchor, say —
-- makes the key claim the entries are current when they are not.
function TS:SyncStructure()
    if self:CurrentRebuildKey() ~= self.builtRebuildKey then
        self:RebuildEntries()
        return true
    end
    return false
end

function TS:ApplyPosition()
    if not self.anchorFrame then return end
    local db = self.db
    KE:ApplyFramePosition(self.anchorFrame, db.Position,
        { anchorFrameType = db.anchorFrameType, ParentFrame = db.ParentFrame, Strata = db.Strata }, true)
end

function TS:RegisterEditMode()
    if not KE.EditMode or self.editModeRegistered then return end
    KE.EditMode:RegisterElement({
        key = "TargetedSpells",
        module = self,
        displayName = "Targeted Spells",
        frame = self.anchorFrame,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            local p = self.db.Position
            p.AnchorTo = pos.AnchorTo
            p.XOffset = pos.XOffset
            p.YOffset = pos.YOffset
            self:ApplyPosition()
        end,
        getAnchorFrom = function() return self.db.Position.AnchorFrom or "CENTER" end,
        getOverlayInset = function() return TS.PreviewStackInset(self.db) end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        guiPath = "TargetedSpells",
    })
    self.editModeRegistered = true
end

---------------------------------------------------------------------------------
-- Entry frames
---------------------------------------------------------------------------------

local function CreateIconFrame(entry, db)
    local f = CreateFrame("Frame", nil, entry)
    f:SetSize(db.IconSize, db.IconSize)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    KE:ApplyIconZoom(f.tex, 0.3)
    KE:AddIconBorders(f)
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints(f)
    f.cooldown:SetDrawEdge(false)
    f.cooldown:SetDrawSwipe(false)
    -- Default minimumCountdownDuration is 2000ms (UI.xsd): sub-2s casts get
    -- NO countdown numbers, so zero it (missing-timer bug — Throw Spear ~1.5s).
    f.cooldown:SetMinimumCountdownDuration(0)
    return f
end

function TS:CreateEntry()
    local db = self.db
    local entry = CreateFrame("Frame", nil, self.anchorFrame)
    entry:SetSize(EntryWidth(db), db.IconSize)

    -- Layout spine: textureless StatusBar whose fill extent mirrors entry
    -- alpha, so invisible entries compact out of the stack. Length covers
    -- the entry + gap.
    entry.Spacer = CreateFrame("StatusBar", nil, entry)
    entry.Spacer:SetStatusBarTexture("")
    entry.Spacer:SetOrientation("VERTICAL")
    entry.Spacer:SetMinMaxValues(0, 1)
    entry.Spacer:SetSize(1, db.IconSize + db.Gap)
    entry.Spacer:SetValue(1)

    entry.leftIcon = CreateIconFrame(entry, db)
    entry.leftIcon:SetPoint("LEFT", entry, "LEFT", 0, 0)
    entry.rightIcon = CreateIconFrame(entry, db)
    entry.rightIcon:SetPoint("RIGHT", entry, "RIGHT", 0, 0)
    entry.rightIcon.cooldown:SetHideCountdownNumbers(true)

    -- Center X: fills the countdown slot while an interrupted entry lingers
    -- (GUI close-button idiom: cross rotated 45°). Capped to the slot width
    -- so a tight TextSpacing never pushes it into the icons. Outline = 8
    -- black offset copies (CustomOutline idiom applied to a texture); the
    -- whole stack sits on one sub-frame so it shows/hides atomically — no
    -- ghosting window.
    local xSize = math.min(db.FontSize * 1.2, db.TextSpacing or 32)
    local xFrame = CreateFrame("Frame", nil, entry)
    xFrame:SetSize(xSize, xSize)
    xFrame:SetPoint("CENTER", entry, "CENTER", 0, 0)
    local px = KE:GetPixelSize()
    local offsets = { {-px,0}, {px,0}, {0,-px}, {0,px},
                      {-px,-px}, {-px,px}, {px,-px}, {px,px} }
    for _, off in ipairs(offsets) do
        local shadow = xFrame:CreateTexture(nil, "OVERLAY", nil, 5)
        shadow:SetSize(xSize, xSize)
        shadow:SetPoint("CENTER", xFrame, "CENTER", off[1], off[2])
        shadow:SetTexture(INTERRUPT_ICON)
        shadow:SetRotation(math.rad(45))
        shadow:SetVertexColor(0, 0, 0, 1)
    end
    local xTex = xFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    xTex:SetAllPoints(xFrame)
    xTex:SetTexture(INTERRUPT_ICON)
    xTex:SetRotation(math.rad(45))
    xTex:SetVertexColor(1, 0.2, 0.2, 1)
    xFrame:Hide()
    entry.interruptX = xFrame

    entry.generation = 0
    return entry
end

---------------------------------------------------------------------------------
-- Entry pool / release
---------------------------------------------------------------------------------

function TS:AcquireEntry(unit)
    local entry = tremove(self.entryPool)
    if not entry then entry = self:CreateEntry() end
    entry.unit = unit
    entry.generation = (entry.generation or 0) + 1
    self.activeEntries[unit] = entry
    self.activeCount = self.activeCount + 1
    entry:Show()
    return entry
end

-- Single funnel for every removal path. Generation guards stale timers and
-- widget callbacks; the interrupt linger suppresses STOP/OnCooldownDone
-- racing in behind an interrupt ("force" = linger timer / nameplate gone).
function TS:Release(entry, generation, reason)
    if not entry or entry.generation ~= generation then return end
    if entry.wasInterrupted and reason ~= "force" then
        if GetTime() < (entry.doNotHideBefore or 0) then
            dbg("release suppressed (linger)", entry.unit, reason)
            return
        end
    end
    dbg("release", entry.unit, reason)
    if self.activeEntries[entry.unit] == entry then
        self.activeEntries[entry.unit] = nil
        self.activeCount = self.activeCount - 1
    end
    entry.generation = entry.generation + 1  -- invalidate pending callbacks
    entry.unit, entry.castBarID, entry.kind = nil, nil, nil
    entry.receiptTime, entry.durationObject = nil, nil
    entry.spellId = nil
    entry.wasInterrupted, entry.doNotHideBefore = nil, nil
    -- Idempotent teardown: pooled frames must come back visually neutral.
    -- Deliberately NO cooldown:Clear() here — a reset must never touch
    -- the Cooldown: replace-by-unit re-acquires this same entry, and Clear +
    -- SetCooldown on one widget in one frame eats the countdown text
    -- (missing-timer bug). Pooled entries are hidden and the next
    -- populate overwrites the cooldown anyway.
    entry:SetAlpha(1)
    entry.Spacer:SetValue(1)
    entry.leftIcon.tex:SetDesaturated(false)
    entry.rightIcon.tex:SetDesaturated(false)
    entry.interruptX:Hide()
    entry.leftIcon.cooldown:SetScript("OnCooldownDone", nil)
    self:HideGlow(entry)
    entry:Hide()
    entry:ClearAllPoints()
    entry.Spacer:ClearAllPoints()
    tinsert(self.entryPool, entry)
    self:RepositionEntries()
end

-- ReleaseAllEntries empties activeEntries first, so Release's active-table
-- bookkeeping no-ops safely; count is reset wholesale.
function TS:ReleaseAllEntries()
    local entries = self.activeEntries
    self.activeEntries = {}
    self.activeCount = 0
    for _, entry in pairs(entries) do
        entry.wasInterrupted = nil
        self:Release(entry, entry.generation, "force")
    end
end

-- Glow runs whenever a spellId exists; the SECRET
-- importance boolean only drives the glow child's alpha (never branched on).
-- Uses the size-parameterized fork with plain db.IconSize — stock LCG reads
-- frame:GetSize(), which returns SECRET numbers anywhere in this entry
-- subtree (its alpha is bound to secret values; rect queries under it are
-- secret so targeting can't be inferred by measuring — BugSack).
function TS:UpdateGlow(entry)
    if not Glows then return end
    if not self.db.GlowImportant or not entry.spellId then
        self:HideGlow(entry)
        return
    end
    local isImportant = C_Spell and C_Spell.IsSpellImportant
        and C_Spell.IsSpellImportant(entry.spellId)
    if type(isImportant) == "nil" then isImportant = false end  -- taint-safe nil check
    local size = self.db.IconSize

    -- Alpha BEFORE show: a parked child keeps the previous cast's alpha,
    -- because the pool resetter that restores alpha 1 never ran on it.
    local left = entry.leftIcon._PixelGlow
    if left then
        left:SetAlphaFromBoolean(isImportant, 1, 0)
        left:Show()
    else
        Glows.PixelGlow_Start(entry.leftIcon, size, size)
        left = entry.leftIcon._PixelGlow
        if left then left:SetAlphaFromBoolean(isImportant, 1, 0) end
    end

    local right = entry.rightIcon._PixelGlow
    if right then
        right:SetAlphaFromBoolean(isImportant, 1, 0)
        right:Show()
    else
        Glows.PixelGlow_Start(entry.rightIcon, size, size)
        right = entry.rightIcon._PixelGlow
        if right then right:SetAlphaFromBoolean(isImportant, 1, 0) end
    end
end

-- Parks the glow: hidden, still attached, ready to be shown again. Cheaper than
-- rebuilding it per cast, which is what releasing to the pool costs.
function TS:HideGlow(entry)
    if not Glows or not entry.leftIcon then return end
    local left = entry.leftIcon._PixelGlow
    if left then left:Hide() end
    local right = entry.rightIcon._PixelGlow
    if right then right:Hide() end
end

-- Retires the glow to its pool. Only for entries that will not be reused: a
-- parked child whose entry is discarded never returns to the pool.
function TS:ReleaseGlow(entry)
    if not Glows or not entry.leftIcon then return end
    Glows.PixelGlow_Stop(entry.leftIcon)
    Glows.PixelGlow_Stop(entry.rightIcon)
end

---------------------------------------------------------------------------------
-- Populate + visibility binding
---------------------------------------------------------------------------------

function TS:RefreshFontCache()
    local db = self.db
    self.cachedFontPath = KE:GetFontPath(db.FontFace)
    self.cachedFontOutline = KE:GetFontOutline(db.FontOutline)
end

-- info: { kind = "cast"|"channel"|"empower", castBarID, name, texture,
--         spellId, duration (LuaDurationObject) }
function TS:PopulateEntry(entry, unit, info)
    local db = self.db
    entry.castBarID = info.castBarID
    entry.kind = info.kind
    entry.spellId = info.spellId
    entry.receiptTime = GetTime()
    entry.durationObject = info.duration
    entry.wasInterrupted, entry.doNotHideBefore = nil, nil
    entry.leftIcon.tex:SetDesaturated(false)
    entry.rightIcon.tex:SetDesaturated(false)
    entry.interruptX:Hide()

    entry.leftIcon.tex:SetTexture(info.texture or FALLBACK_ICON)
    entry.rightIcon.tex:SetTexture(info.texture or FALLBACK_ICON)

    local lc, rc = entry.leftIcon.cooldown, entry.rightIcon.cooldown
    lc:SetHideCountdownNumbers(false)
    lc:SetCountdownFormatter(GetCastFormatter(db.Decimals))
    lc:SetCooldownFromDurationObject(info.duration)
    rc:SetCooldownFromDurationObject(info.duration)

    -- Widget-managed FontString: the Cooldown resets font/anchors on
    -- Clear()/SetCooldown, so re-apply everything on every populate.
    local fs = lc:GetCountdownFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", entry, "CENTER", 0, 0)
        local ok = pcall(fs.SetFont, fs, self.cachedFontPath, db.FontSize,
            self.cachedFontOutline)
        if not ok then
            pcall(fs.SetFont, fs, KE:GetFontPath("Expressway"), db.FontSize, "OUTLINE")
        end
        local c = db.FontColor
        if c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    end

    -- Capture the generation NOW (interrupt-timer idiom): reading
    -- entry.generation at fire time always matches, turning the stale-guard
    -- into a no-op — a late done event queued by the widget would then
    -- release the entry's NEXT occupant.
    local gen = entry.generation
    lc:SetScript("OnCooldownDone", function()
        TS:Release(entry, gen, "cooldown-done")
    end)

    -- Missing-timer probe: report the countdown FontString's
    -- health 0.3s after populate. Only plain values are read — never the
    -- text/offsets, which are secret-derived on this subtree in combat.
    if DEBUG_TS then
        dbg("populate", unit, info.kind, "fs=" .. tostring(fs ~= nil))
        C_Timer.After(0.3, function()
            if entry.generation ~= gen then return end
            local okProbe, report = pcall(function()
                local f2 = lc:GetCountdownFontString()
                if not f2 then return "fs=nil" end
                local point, rel = f2:GetPoint(1)
                local fontPath = f2:GetFont()
                local fontMatch = "<secret>"
                if not (issecretvalue and issecretvalue(fontPath)) then
                    fontMatch = tostring(fontPath == KE:GetFontPath(TS.db.FontFace))
                end
                return "shown=" .. describeValue(f2:IsShown())
                    .. " relIsEntry=" .. tostring(rel == entry)
                    .. " point=" .. describeValue(point)
                    .. " ourFont=" .. fontMatch
            end)
            dbg("fs@0.3", unit, okProbe and report or ("probe error: " .. tostring(report)))
        end)
    end

    -- THE verbatim core (spec "Visibility binding"): the secret targeting
    -- boolean never enters Lua; durationAlpha doubles as the >60s gate; the
    -- spacer mirrors alpha so hidden entries compact out of the stack.
    local durationAlpha = info.duration:EvaluateRemainingDuration(KE.curves.IsLongCast)
    entry:SetAlpha(durationAlpha)
    entry.Spacer:SetValue(durationAlpha)
    entry:SetAlphaFromBoolean(PlayerIsSpellTarget(unit), durationAlpha, 0)
    entry.Spacer:SetValue(entry:GetAlpha())

    self:UpdateGlow(entry)
end

---------------------------------------------------------------------------------
-- Layout (spacer chain)
---------------------------------------------------------------------------------

function TS:RepositionEntries()
    local db = self.db
    local list = wipe(self.sortScratch)
    for _, entry in pairs(self.activeEntries) do tinsert(list, entry) end
    tsort(list, TS.CompareEntries)

    local growDown = (db.Grow or "DOWN") == "DOWN"
    local point = growDown and "TOP" or "BOTTOM"
    local relPoint = growDown and "BOTTOM" or "TOP"
    local prevTexture
    for i, entry in ipairs(list) do
        local spacer = entry.Spacer
        -- Fill from the anchored edge so a zero-value spacer's texture edge
        -- collapses to the chain point.
        spacer:SetReverseFill(growDown)
        spacer:ClearAllPoints()
        spacer:SetPoint(point, (i == 1) and self.anchorFrame or prevTexture, relPoint, 0, 0)
        entry:ClearAllPoints()
        entry:SetPoint(point, spacer, point, 0, 0)
        prevTexture = spacer:GetStatusBarTexture()
    end
end

---------------------------------------------------------------------------------
-- Cast start pipeline
---------------------------------------------------------------------------------

-- Combat leads: it rejects the most, and it is the gate a later edit is most
-- likely to drop. Shards deliver nameplate tokens only, so no token test here.
local function IsRelevantUnit(unit)
    return unit
        and UnitAffectingCombat(unit)
        and UnitExists(unit)
        and UnitCanAttack("player", unit)
end
TS.IsRelevantUnit = IsRelevantUnit

-- Every delayed-start dispatch (event-driven or scan/retarget-driven) bumps
-- the unit's token before scheduling; TryStart aborts unless its token is
-- still the latest, coalescing a superseded dispatch WITHOUT comparing any
-- secret cast id — the token is a plain per-unit counter.
function TS:BumpDispatchToken(unit)
    local token = (self.pendingDispatch[unit] or 0) + 1
    self.pendingDispatch[unit] = token
    return token
end

-- Delayed re-read: cast target/duration data settles ~0.2s after the event.
-- The dispatch token (not any cast id) aborts the
-- handler once a later dispatch has superseded it for this unit.
function TS:TryStart(unit, token)
    if not self.contentActive then return end
    if not IsRelevantUnit(unit) then return end
    if self.pendingDispatch[unit] ~= token then
        dbg("stale delayed start (superseded)", unit)
        return
    end

    local info
    -- castID (position 7) is a SECRET WOWGUID — never bound. castBarID
    -- (position 10) is the plain NeverSecret correlation id 12.0 added
    -- specifically so addons don't have to touch the secret one.
    local name, _, texture, _, _, _, _, _, spellID, castBarID = UnitCastingInfo(unit)
    if name then
        local duration = UnitCastingDuration(unit)
        if not duration then return end
        info = { kind = "cast", castBarID = castBarID,
                 name = name, texture = texture, spellId = spellID, duration = duration }
    else
        -- Empowered casts report through UnitChannelInfo with isEmpowered set
        -- and use UnitEmpoweredChannelDuration — KE's own CastbarHelpers
        -- H.StartCast is the shipped precedent (CastbarHelpers.lua).
        -- castBarID here is UnitChannelInfo's 11th return (plain, NeverSecret).
        local cname, _, ctexture, _, _, _, _, cspellID, isEmpowered, _, ccastBarID = UnitChannelInfo(unit)
        if not cname then return end
        local duration
        if isEmpowered then
            duration = UnitEmpoweredChannelDuration(unit)
        else
            duration = UnitChannelDuration(unit)
        end
        if not duration then return end
        info = { kind = isEmpowered and "empower" or "channel", castBarID = ccastBarID,
                 name = cname, texture = ctexture, spellId = cspellID, duration = duration }
    end

    local entry = self.activeEntries[unit]
    if entry then
        self:Release(entry, entry.generation, "force")   -- replace-by-unit
    elseif self.activeCount >= (self.db.MaxIcons or 10) then
        dbg("at cap, ignoring", unit)
        return
    end
    entry = self:AcquireEntry(unit)
    self:PopulateEntry(entry, unit, info)
    self:RepositionEntries()
    -- info.name is a secret string on hostile units — never print it.
    dbg("started", unit, info.kind)
end

function TS:DiscardPendingCasts()
    self.pendingCasts = {}
    self.pendingHead = 1
    self.pendingTail = 0
    self.drainScheduled = false
    self.drainEpoch = self.drainEpoch + 1
end

function TS:ScheduleDrain(delay)
    if self.drainScheduled then return end
    self.drainScheduled = true
    local epoch = self.drainEpoch
    C_Timer.After(delay, function() TS:DrainPendingCasts(epoch) end)
end

function TS:DrainPendingCasts(epoch)
    if epoch ~= self.drainEpoch then return end
    self.drainScheduled = false

    local pending, now = self.pendingCasts, GetTime()
    local stop = TS.FirstNotDue(pending, self.pendingHead, self.pendingTail, now)
    for i = self.pendingHead, stop - 1 do
        local info = pending[i]
        pending[i] = nil
        self:TryStart(info.unit, info.token)
    end
    self.pendingHead = stop

    if self.pendingHead > self.pendingTail then
        self.pendingCasts = {}
        self.pendingHead = 1
        self.pendingTail = 0
        return
    end

    self:ScheduleDrain(pending[self.pendingHead].dueAt - now)
end

function TS:OnCastEvent(event, unit, ...)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        -- Deliberately NOT relevance-filtered here. The settle delay exists so a
        -- cast can be re-read once its data lands, and discarding now would drop
        -- a unit that becomes relevant during the window. TryStart re-checks.
        local now = GetTime()
        local tail = self.pendingTail + 1
        self.pendingCasts[tail] = {
            unit = unit,
            token = self:BumpDispatchToken(unit),
            dueAt = now + SETTLE_DELAY,
        }
        self.pendingTail = tail
        self:ScheduleDrain(SETTLE_DELAY)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- Payload: castGUID, spellID, interruptedBy, castBarID (plain, NeverSecret).
        local castBarID = select(4, ...)
        self:OnInterrupted(unit, castBarID)
    else -- STOP / CHANNEL_STOP / EMPOWER_STOP
        local castBarID
        if event == "UNIT_SPELLCAST_STOP" then
            castBarID = select(3, ...)                    -- castGUID, spellID, castBarID
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            castBarID = select(4, ...)                    -- +interruptedBy before castBarID
        elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            castBarID = select(5, ...)                    -- +complete, interruptedBy before castBarID
        end
        local entry = self.activeEntries[unit]
        if entry and (not entry.castBarID or not castBarID or entry.castBarID == castBarID) then
            self:Release(entry, entry.generation, "stop")
        end
    end
end

function TS:OnInterrupted(unit, castBarID)
    local entry = self.activeEntries[unit]
    if not entry then return end
    if entry.castBarID and castBarID and entry.castBarID ~= castBarID then return end
    if not self.db.IndicateInterrupts then
        self:Release(entry, entry.generation, "stop")
        return
    end
    dbg("interrupted", unit)
    entry.wasInterrupted = true
    entry.doNotHideBefore = GetTime() + INTERRUPT_HOLD
    entry.leftIcon.tex:SetDesaturated(true)
    entry.rightIcon.tex:SetDesaturated(true)
    -- Interrupted look: X on, countdown numbers off, glow off.
    entry.interruptX:Show()
    entry.leftIcon.cooldown:SetHideCountdownNumbers(true)
    self:HideGlow(entry)
    local gen = entry.generation
    C_Timer.After(INTERRUPT_LINGER, function()
        TS:Release(entry, gen, "force")
    end)
end

-- Scan/added/retarget paths run synchronously:
-- the settle delay exists because a FRESH cast's target/duration data lags
-- the START event — a cast discovered already in flight is settled, and
-- delaying it just shows the entry 0.2s late for nothing.
function TS:ScanExistingNameplates()
    for i = 1, MAX_NAMEPLATE_TOKENS do
        local unit = "nameplate" .. i
        if IsRelevantUnit(unit) then
            self:TryStart(unit, self:BumpDispatchToken(unit))
        end
    end
end

function TS:OnNameplateAdded(_, unit)
    if self.contentActive and IsRelevantUnit(unit) then
        self:TryStart(unit, self:BumpDispatchToken(unit))
    end
end

function TS:OnNameplateRemoved(_, unit)
    -- pendingDispatch[unit] is deliberately NOT cleared: keeping the counter
    -- monotonic closes the token-collision window when a nameplate token is
    -- recycled to a new mob within the settle delay (bounded by the nameplate
    -- token range).
    local entry = self.activeEntries[unit]
    if entry then
        entry.wasInterrupted = nil
        self:Release(entry, entry.generation, "force")
    end
end

function TS:OnUnitTarget(_, unit)
    -- Retarget mid-cast rebuilds the binding; ALSO the first-target case is
    -- covered: a mob that starts casting untargeted and acquires you during the
    -- settle window shows NOW, not at +0.2s — so no existing-entry gate.
    -- Relevance is checked BEFORE the bump: bumping for a unit that cannot
    -- start supersedes a queued dispatch that would have succeeded.
    if not IsRelevantUnit(unit) then return end
    self:TryStart(unit, self:BumpDispatchToken(unit))
end

---------------------------------------------------------------------------------
-- Settings application / preview
---------------------------------------------------------------------------------

-- Structural keys (IconSize/Gap/Grow/Font*/MaxIcons) invalidate pooled frame
-- geometry: drop the pool and re-derive everything.
function TS:RebuildEntries()
    -- Any rebuild already queued has now been done, so let a later change queue
    -- a fresh one. The pending timer standing down is SyncStructure's job, not
    -- this flag's.
    self._rebuildQueued = false

    -- Hide (and pool) any preview entries FIRST so the stale-geometry frames
    -- are dropped with the rest of the pool below, then re-show after the
    -- rebuild so the GUI preview reflects the new settings.
    local wasPreview = self.isPreview
    self:HidePreview()
    -- A rebuild drops the pool a queued cast would have populated.
    self:DiscardPendingCasts()
    self:ReleaseAllEntries()
    for _, entry in ipairs(self.entryPool) do
        -- A parked child on a discarded entry never returns to the glow pool.
        self:ReleaseGlow(entry)
        entry:SetParent(nil)
        entry:Hide()
    end
    self.entryPool = {}
    if self.anchorFrame then
        self.anchorFrame:SetSize(EntryWidth(self.db), self.db.IconSize)
    end
    -- Stamped HERE and nowhere else: this is the only function that drops the
    -- pool, so it is the only one that can honestly claim the frames match.
    self:RefreshFontCache()
    self.builtRebuildKey = self:CurrentRebuildKey()
    self:ApplyPosition()
    if wasPreview then self:ShowPreview() end
    self:CheckContentGate()

    -- The overlay box is computed from these settings and is only recomputed on
    -- request, so it would otherwise keep the previous numbers until something
    -- unrelated refreshed it.
    if KE.EditMode then KE.EditMode:RefreshLiveState() end
end

-- Structural sliders fire during drag (~100ms throttle); coalesce so a drag
-- costs one rebuild instead of orphaning a pool per tick.
function TS:QueueRebuild()
    if self._rebuildQueued then return end
    self._rebuildQueued = true
    -- The question is re-asked at fire time rather than answered now. A quarter
    -- second is long enough for a profile switch, and a switch can leave this
    -- timer wanting a rebuild nobody needs any more: the pool may have been
    -- rebuilt already, the new profile's settings may match what is built, or
    -- the module may be off. Frames are never collected, so an unwanted rebuild
    -- orphans a whole pool. SyncStructure answers all three by comparing the
    -- key that is live when the timer actually runs.
    C_Timer.After(0.25, function()
        TS._rebuildQueued = false
        if not (TS.db and TS.db.Enabled) then return end
        TS:SyncStructure()
    end)
end

-- In-place keys (GlowImportant / IndicateInterrupts / content checkboxes):
-- re-apply to live entries, re-evaluate the gate immediately.
function TS:ApplySettings()
    self:UpdateDB()

    -- A profile switch can change the geometry settings without any slider
    -- moving, and this is the function it reaches. RebuildEntries finishes the
    -- job on its own, including the content gate, so stop here rather than
    -- walking a glow loop over entries it has already released.
    if self:SyncStructure() then return end

    -- Position, parent and strata are profile settings too, and a switch that
    -- leaves this module enabled reaches only here. The GUI's own position
    -- callback does not fire on that path, and RebuildEntries — the only other
    -- thing that re-applies them — did not run or we would have returned above.
    self:ApplyPosition()

    for _, entry in pairs(self.activeEntries) do
        self:UpdateGlow(entry)
    end
    self:CheckContentGate()
end

local PREVIEW_ENTRIES = {
    { icon = 135846, duration = 8 },   -- Frostbolt
    { icon = 136197, duration = 5 },   -- Shadow Bolt
}
-- The overlay box is sized from PREVIEW_ENTRY_COUNT, declared with the other
-- constants because the edit-mode registration is parsed before this table.
assert(#PREVIEW_ENTRIES == PREVIEW_ENTRY_COUNT)

function TS:ShowPreview()
    self:UpdateDB()
    self:CreateAnchorFrame()
    self:ApplyPosition()
    self:HidePreview()
    self.isPreview = true
    self.anchorFrame:Show()
    self.previewEntries = {}
    self.previewTickers = {}
    local db = self.db
    -- The Cooldown widget resets its FontString on SetCooldown, so every
    -- (re)start re-applies anchor + font.
    local function startCooldowns(entry, p)
        local now = GetTime()
        entry.leftIcon.cooldown:SetCooldown(now, p.duration)
        entry.rightIcon.cooldown:SetCooldown(now, p.duration)
        local fs = entry.leftIcon.cooldown:GetCountdownFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", entry, "CENTER", 0, 0)
            pcall(fs.SetFont, fs, KE:GetFontPath(db.FontFace), db.FontSize,
                KE:GetFontOutline(db.FontOutline))
            local c = db.FontColor
            if c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
        end
    end
    local now = GetTime()
    for i, p in ipairs(PREVIEW_ENTRIES) do
        local entry = tremove(self.entryPool) or self:CreateEntry()
        entry.receiptTime = now + i
        entry.leftIcon.tex:SetTexture(p.icon)
        entry.rightIcon.tex:SetTexture(p.icon)
        -- Plain-number cooldown path: previews never touch secret values.
        entry.leftIcon.cooldown:SetHideCountdownNumbers(false)
        entry.leftIcon.cooldown:SetCountdownFormatter(GetCastFormatter(db.Decimals))
        startCooldowns(entry, p)
        -- Looping timers (DungeonTimers text-mode preview pattern): each
        -- entry restarts its own countdown when it runs out.
        tinsert(self.previewTickers, C_Timer.NewTicker(p.duration, function()
            startCooldowns(entry, p)
        end))
        entry:Show()
        tinsert(self.previewEntries, entry)
    end
    -- Chain the preview entries exactly like live ones.
    local saveActive, saveCount = self.activeEntries, self.activeCount
    self.activeEntries, self.activeCount = {}, 0
    for i, e in ipairs(self.previewEntries) do
        self.activeEntries["preview" .. i] = e
        self.activeCount = self.activeCount + 1
    end
    self:RepositionEntries()
    self.activeEntries, self.activeCount = saveActive, saveCount
end

function TS:HidePreview()
    self.isPreview = false
    if self.previewTickers then
        for _, ticker in ipairs(self.previewTickers) do ticker:Cancel() end
        self.previewTickers = nil
    end
    if self.previewEntries then
        for _, entry in ipairs(self.previewEntries) do
            entry:Hide()
            entry:ClearAllPoints()
            entry.Spacer:ClearAllPoints()
            entry.leftIcon.cooldown:Clear()
            entry.rightIcon.cooldown:Clear()
            self:HideGlow(entry)
            tinsert(self.entryPool, entry)
        end
        self.previewEntries = nil
    end
    self:CheckContentGate()
end

---------------------------------------------------------------------------------
-- CVar Prompt
---------------------------------------------------------------------------------

-- Field write only — never reassign the StaticPopupDialogs global itself:
-- that taints the _G slot and every secure popup read (talent-commit confirm
-- included) then carries KE taint into OverlayPlayerCastingBarFrame.
StaticPopupDialogs["KE_TARGETEDSPELLS_CVAR"] = {
    text = "Targeted Spells: enemies casting from off-screen only produce nameplates when 'nameplateShowOffscreen' is enabled. Turn it on now?",
    button1 = "Enable it",
    button2 = "No thanks",
    OnAccept = function()
        SetCVar("nameplateShowOffscreen", "1")
        KE:Print("nameplateShowOffscreen enabled.")
    end,
    OnCancel = function()
        local db = KE.db and KE.db.profile.TargetedSpells
        if db then db.CVarDeclined = true end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    noCancelOnEscape = true,  -- Escape = soft dismiss (prompt returns next enable); only the button declines permanently
    preferredIndex = 3,
}

function TS:CheckCVarPrompt()
    local db = self.db
    if not db or db.CVarDeclined then return end
    if GetCVar("nameplateShowOffscreen") ~= "1" then
        StaticPopup_Show("KE_TARGETEDSPELLS_CVAR")
    end
end

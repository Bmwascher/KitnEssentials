-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrashConfig.lua                                         ║
-- ║  Per-ability override backend for the Dungeon Trash      ║
-- ║  Tracker — the Get/Set/Has/Reset accessors the dungeon   ║
-- ║  config pages drive, plus the curated-default resolvers  ║
-- ║  the renderer reads through.                             ║
-- ║                                                          ║
-- ║  Trash overrides key by "mapID:npcID:spellID" (the same  ║
-- ║  spellID recurs across dungeons/mobs, so mapID+npcID     ║
-- ║  disambiguate). Accessors take an EXPLICIT mapID and read║
-- ║  the profile DB directly — the config UI must work even  ║
-- ║  when the module is disabled (self.db is only bound on   ║
-- ║  OnEnable), and the page knows its dungeon's mapID.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local DTrash = KitnEssentials:GetModule("DungeonTrash", true)
if not DTrash then return end

local string_format = string.format
local ipairs = ipairs
local pairs = pairs

-- The override tables the config surface writes, all keyed "mapID:npcID:spellID".
local OVERRIDE_TABLES = {
    "SpellDisabled",
    "SpellColorOverrides",
    "SpellDisplayOverrides",
    "SpellNameplateOverrides",
    "SpellRoleOverrides",
    "SpellSoundOverrides",
    "SpellLabelOverrides",
    "SpellRevealOverrides",
    "SpellDecimalThresholds",
}

local function overrideKey(mapID, npcID, spellID)
    return string_format("%d:%d:%d", mapID or 0, npcID or 0, spellID or 0)
end

-- Profile DB directly (NOT self.db) so overrides are editable while disabled.
local function profileDB()
    return KE.db and KE.db.profile and KE.db.profile.DungeonTrash
end

local function ovTable(name)
    local db = profileDB()
    if not db then return nil end
    db[name] = db[name] or {}
    return db[name]
end

-- Curated spell entry for (mapID, npcID, spellID), or nil.
local function curatedSpell(mapID, npcID, spellID)
    local dungeon = KE.TrashData and KE.TrashData[mapID]
    local mob = dungeon and dungeon.mobs and dungeon.mobs[npcID]
    return mob and mob.spells and mob.spells[spellID]
end

-- Hand-maintained curation overlay (TrashCurated.lua) for (mapID, npcID,
-- spellID), or nil — KE's shipped label/display defaults that survive data
-- re-extraction. Sits between the user's GUI overrides and the extracted data.
local function curatedOverlay(mapID, npcID, spellID)
    local d = KE.TrashCurated and KE.TrashCurated[mapID]
    local m = d and d[npcID]
    return m and m[spellID]
end

-- Shipped default display mode when neither a user override nor the curation
-- overlay pins one (deliberate default: text).
local CURATED_DEFAULT_DISPLAY = "text"

-- Reverse lookup used by the GUI: dungeonKey → the TrashData entry (mapID+mobs).
function DTrash:TrashDungeonByKey(dungeonKey)
    if not KE.TrashData then return nil end
    for _, d in pairs(KE.TrashData) do
        if d.dungeonKey == dungeonKey then return d end
    end
    return nil
end

-- ── Enable ──────────────────────────────────────────────────────────────────

function DTrash:SetSpellDisabled(mapID, npcID, spellID, disabled)
    local t = ovTable("SpellDisabled"); if not t then return end
    t[overrideKey(mapID, npcID, spellID)] = disabled and true or nil
    -- Re-ENABLE recovery: KE's arms are one-shot, so a mid-dungeon disable
    -- consumed the spell's armed output at fire time (deferred reveals died
    -- at their gate re-check; the marker prune deleted stored predictions)
    -- and nothing else ever re-reads the still-correct anchors — the spell
    -- stayed output-dead until its next COMPLETED cast. The reference
    -- recovers within one refresh via its config-revision schedule rebuild;
    -- re-arming the affected runtimes from their anchors reproduces that.
    if not disabled and self.monitoring and mapID == self.currentMapID then
        for _, rt in pairs(self.tracked) do
            if rt.matchedNPCID == npcID then
                self:ReArmFromAnchors(rt, true)
            end
        end
    end
end

function DTrash:GetSpellDisabled(mapID, npcID, spellID)
    local db = profileDB()
    local t = db and db.SpellDisabled
    return (t and t[overrideKey(mapID, npcID, spellID)] == true) or false
end

-- ── Color ───────────────────────────────────────────────────────────────────

-- nil color clears the override (float compares are unreliable, so no prune —
-- an explicit reset restores the built-in DEFAULT_TRASH_COLOR).
function DTrash:SetSpellColorOverride(mapID, npcID, spellID, color)
    local t = ovTable("SpellColorOverrides"); if not t then return end
    local key = overrideKey(mapID, npcID, spellID)
    if color then
        t[key] = { color[1], color[2], color[3] }
    else
        t[key] = nil
    end
end

function DTrash:GetSpellColorOverride(mapID, npcID, spellID)
    local db = profileDB()
    local t = db and db.SpellColorOverrides
    return t and t[overrideKey(mapID, npcID, spellID)] or nil
end

-- Fallback color when no per-ability override or preset matches. Single owner:
-- this file loads before TrashOutput (Trash.xml), which aliases the module
-- field — one value, no keep-in-sync mirror.
DTrash.DEFAULT_TRASH_COLOR = { 0.3, 0.5, 0.9 }
local DEFAULT_TRASH_COLOR = DTrash.DEFAULT_TRASH_COLOR

-- Effective color (override → default) — the config swatch shows THIS so an
-- unset ability displays its real alert color rather than a blank white.
function DTrash:GetSpellEffectiveColor(mapID, npcID, spellID)
    local ov = self:GetSpellColorOverride(mapID, npcID, spellID)
    if ov then return ov end
    if KE.ResolveTrashPresetColor then
        -- An explicit colorKey pins the colour to a preset independent of the
        -- label — used to keep a real spell name yet borrow a preset's colour
        -- (e.g. an interrupt shown as "Fire Spit" in KICK red).
        local o = curatedOverlay(mapID, npcID, spellID)
        if o and o.colorKey then
            local c = KE.ResolveTrashPresetColor(o.colorKey)
            if c then return c end
        end
        -- Otherwise the colour follows the EFFECTIVE label through the shared boss
        -- preset palette (SOAK→green, DODGE→orange, …); unmatched → flat default.
        local c = KE.ResolveTrashPresetColor(self:GetSpellLabel(mapID, npcID, spellID))
        if c then return c end
    end
    return DEFAULT_TRASH_COLOR
end

-- ── Display (bar / text) ────────────────────────────────────────────────────

-- Shipped default display: curation overlay wins, else the flat author default
-- (text). The extracted per-spell `display` is intentionally NOT consulted —
-- KE curates its own bar/text exceptions in TrashCurated.lua.
function DTrash:GetSpellCuratedDisplay(mapID, npcID, spellID)
    local o = curatedOverlay(mapID, npcID, spellID)
    if o and (o.display == "bar" or o.display == "text") then return o.display end
    return CURATED_DEFAULT_DISPLAY
end

function DTrash:SetSpellDisplayOverride(mapID, npcID, spellID, mode)
    local t = ovTable("SpellDisplayOverrides"); if not t then return end
    local key = overrideKey(mapID, npcID, spellID)
    -- Prune back to the curated default rather than storing a redundant entry.
    if mode == self:GetSpellCuratedDisplay(mapID, npcID, spellID) then
        t[key] = nil
    else
        t[key] = (mode == "text") and "text" or "bar"
    end
end

function DTrash:GetSpellDisplay(mapID, npcID, spellID)
    local db = profileDB()
    local t = db and db.SpellDisplayOverrides
    local o = t and t[overrideKey(mapID, npcID, spellID)]
    return o or self:GetSpellCuratedDisplay(mapID, npcID, spellID)
end

-- ── Show on nameplate ───────────────────────────────────────────────────────

function DTrash:GetSpellCuratedNameplate(mapID, npcID, spellID)
    local s = curatedSpell(mapID, npcID, spellID)
    if s and s.showNameplate == false then return false end
    return true  -- curated default is on
end

function DTrash:SetSpellNameplateOverride(mapID, npcID, spellID, show)
    local t = ovTable("SpellNameplateOverrides"); if not t then return end
    local key = overrideKey(mapID, npcID, spellID)
    local want = show and true or false
    if want == self:GetSpellCuratedNameplate(mapID, npcID, spellID) then
        t[key] = nil  -- prune to curated default
    else
        t[key] = want
    end
end

function DTrash:GetSpellShowNameplate(mapID, npcID, spellID)
    local db = profileDB()
    local t = db and db.SpellNameplateOverrides
    local o = t and t[overrideKey(mapID, npcID, spellID)]
    if o ~= nil then return o end
    return self:GetSpellCuratedNameplate(mapID, npcID, spellID)
end

-- ── Role ("who sees it") ─────────────────────────────────────────────────────

-- Curated roles ship per spell as { tank=, healer=, dps= }; absent = all roles.
local ALL_ROLES = { tank = true, healer = true, dps = true }

function DTrash:GetSpellCuratedRoles(mapID, npcID, spellID)
    local o = curatedOverlay(mapID, npcID, spellID)
    if o and type(o.roles) == "table" then return o.roles end
    local s = curatedSpell(mapID, npcID, spellID)
    local r = s and s.roles
    if type(r) ~= "table" then return ALL_ROLES end
    return r
end

-- Effective role set (override → curated). Always a {tank,healer,dps} table.
function DTrash:GetSpellEffectiveRoles(mapID, npcID, spellID)
    local db = profileDB()
    local o = db and db.SpellRoleOverrides and db.SpellRoleOverrides[overrideKey(mapID, npcID, spellID)]
    if type(o) == "table" then return o end
    return self:GetSpellCuratedRoles(mapID, npcID, spellID)
end

-- Toggle one role. Starts from the current effective set so the other two are
-- preserved, and prunes back to nil when the result equals the curated default.
function DTrash:SetSpellRoleOverride(mapID, npcID, spellID, roleKey, enabled)
    local t = ovTable("SpellRoleOverrides"); if not t then return end
    local key = overrideKey(mapID, npcID, spellID)
    local cur = self:GetSpellEffectiveRoles(mapID, npcID, spellID)
    local want = {
        tank = cur.tank and true or false,
        healer = cur.healer and true or false,
        dps = cur.dps and true or false,
    }
    want[roleKey] = enabled and true or false
    local c = self:GetSpellCuratedRoles(mapID, npcID, spellID)
    if want.tank == (c.tank and true or false)
        and want.healer == (c.healer and true or false)
        and want.dps == (c.dps and true or false) then
        t[key] = nil
    else
        t[key] = want
    end
end

-- Would the player's assigned role see this spell's alert? Fails OPEN on an
-- unknown role (the player's own role is not a secret value in 12.0).
local ROLE_MAP = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
function DTrash:PlayerSeesTrashSpell(mapID, npcID, spellID)
    local roles = self:GetSpellEffectiveRoles(mapID, npcID, spellID)
    if type(roles) ~= "table" then return true end
    local assigned = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    local myRole = assigned and ROLE_MAP[assigned]
    if not myRole then return true end
    return roles[myRole] and true or false
end

-- ── Sounds (Actions) ─────────────────────────────────────────────────────────
-- Stored as { onShow=<lsmName>, onHide=<lsmName>, onCastStart=<lsmName> } per
-- key; any may be nil. onShow fires at the alert reveal and onHide at
-- countdown-zero — both PREDICTION-driven; onCastStart fires the moment the
-- mob's real cast bar is observed (see DTrash:PlayObservedCastStartCue).
--
-- onCastStart alone is THREE-STATE, mirroring the boss timers' curated sound
-- model (there the curated default rides the On Show slot; for trash it rides
-- Cast Start): nil = inherit the curated default from the TrashCurated
-- overlay's `castSound`, literal "None" = user explicitly muted, anything
-- else = the user's own LSM pick. Playback and the GUI dropdown both read
-- GetEffectiveSpellSoundOnCastStart, never the raw stored value.

local function soundEntry(mapID, npcID, spellID)
    local db = profileDB()
    local t = db and db.SpellSoundOverrides
    return t and t[overrideKey(mapID, npcID, spellID)]
end

function DTrash:GetSpellSoundOnShow(mapID, npcID, spellID)
    local e = soundEntry(mapID, npcID, spellID)
    return e and e.onShow or nil
end

function DTrash:GetSpellSoundOnHide(mapID, npcID, spellID)
    local e = soundEntry(mapID, npcID, spellID)
    return e and e.onHide or nil
end

function DTrash:GetSpellSoundOnCastStart(mapID, npcID, spellID)
    local e = soundEntry(mapID, npcID, spellID)
    return e and e.onCastStart or nil
end

-- Shipped cast-start default from the curation overlay (TrashCurated.lua).
function DTrash:GetCuratedCastStartSound(mapID, npcID, spellID)
    local o = curatedOverlay(mapID, npcID, spellID)
    return o and o.castSound or nil
end

-- Resolves the cast-start three-state into the LSM key playback should use.
-- Returns nil for "play nothing" (explicit "None" mute, or no override and
-- no curated default).
function DTrash:GetEffectiveSpellSoundOnCastStart(mapID, npcID, spellID)
    local override = self:GetSpellSoundOnCastStart(mapID, npcID, spellID)
    if override == "None" then return nil end
    if override then return override end
    return self:GetCuratedCastStartSound(mapID, npcID, spellID)
end

-- "Does anything actually play?" — drives the list rows' "S" badge. Reads
-- EFFECTIVE state like the boss timers' HasSpellSound: a curated castSound
-- default lights it with no override stored, and a stored "None" (mute)
-- doesn't count as a sound.
function DTrash:HasSpellSound(mapID, npcID, spellID)
    local onShow = self:GetSpellSoundOnShow(mapID, npcID, spellID)
    local onHide = self:GetSpellSoundOnHide(mapID, npcID, spellID)
    return (onShow ~= nil and onShow ~= "None")
        or (onHide ~= nil and onHide ~= "None")
        or (self:GetEffectiveSpellSoundOnCastStart(mapID, npcID, spellID) ~= nil)
end

local function setSound(self, mapID, npcID, spellID, field, sound)
    local t = ovTable("SpellSoundOverrides"); if not t then return end
    local key = overrideKey(mapID, npcID, spellID)
    local e = t[key] or {}
    e[field] = (sound ~= nil and sound ~= "") and sound or nil
    if e.onShow == nil and e.onHide == nil and e.onCastStart == nil then
        t[key] = nil
    else
        t[key] = e
    end
end

function DTrash:SetSpellSoundOnShow(mapID, npcID, spellID, sound)
    setSound(self, mapID, npcID, spellID, "onShow", sound)
end

function DTrash:SetSpellSoundOnHide(mapID, npcID, spellID, sound)
    setSound(self, mapID, npcID, spellID, "onHide", sound)
end

function DTrash:SetSpellSoundOnCastStart(mapID, npcID, spellID, sound)
    setSound(self, mapID, npcID, spellID, "onCastStart", sound)
end

-- ── Label / display text ─────────────────────────────────────────────────────

function DTrash:GetSpellCuratedLabel(mapID, npcID, spellID)
    local o = curatedOverlay(mapID, npcID, spellID)
    if o and o.label and o.label ~= "" then return o.label end
    local s = curatedSpell(mapID, npcID, spellID)
    return (s and s.name) or "Trash"
end

-- Custom label (preset chips write here too). Prunes to nil when blank or equal
-- to the curated name.
function DTrash:SetSpellLabelOverride(mapID, npcID, spellID, text)
    local t = ovTable("SpellLabelOverrides"); if not t then return end
    local key = overrideKey(mapID, npcID, spellID)
    if text == nil or text == "" or text == self:GetSpellCuratedLabel(mapID, npcID, spellID) then
        t[key] = nil
    else
        t[key] = text
    end
end

function DTrash:GetSpellLabel(mapID, npcID, spellID)
    local db = profileDB()
    local t = db and db.SpellLabelOverrides
    local o = t and t[overrideKey(mapID, npcID, spellID)]
    return o or self:GetSpellCuratedLabel(mapID, npcID, spellID)
end

-- Raw stored override (nil when unset). The Display-tab editbox binds to THIS
-- so an un-customized ability shows an empty field rather than the curated
-- name pre-filled — matches the boss Custom Label editbox behavior.
function DTrash:GetSpellLabelOverride(mapID, npcID, spellID)
    local db = profileDB()
    local t = db and db.SpellLabelOverrides
    return t and t[overrideKey(mapID, npcID, spellID)] or nil
end

-- ── Reveal window (lead time before the predicted cast) ──────────────────────
-- Trash has no curated reveal value; the effective default is the shared
-- DungeonTimers group ShowAtSeconds (per-mode floor text 5 / bar 10). A per-ability override sets
-- how many seconds before the predicted cast the alert appears. Unlike the boss
-- "0 = always visible", trash alerts are pure countdowns with no spawn moment,
-- so the GUI slider clamps to a 1s minimum — 0 has no meaning here.
-- Per-mode reveal floor, used when the shared group value is unset or <= 0 (a
-- boss stack set to "always visible", which is meaningless for a pure-countdown
-- trash alert). Reads the SHIPPED BarGroup/TextGroup ShowAtSeconds defaults
-- through KE:GetDefaultDB() so a future retune propagates here automatically;
-- the literal 5/10 floor only backstops a missing defaults table (headless).
local function trashRevealFloor(mode)
    local d = KE.GetDefaultDB and KE:GetDefaultDB()
    local dt = d and d.profile and d.profile.DungeonTimers
    local g = dt and ((mode == "text") and dt.TextGroup or dt.BarGroup)
    local v = g and tonumber(g.ShowAtSeconds)
    if v and v > 0 then return v end
    return (mode == "text") and 5 or 10
end

local function revealGroupDefault(mapID, npcID, spellID)
    local mode = DTrash:GetSpellDisplay(mapID, npcID, spellID)
    local fallback = trashRevealFloor(mode)
    local dt = KE.db and KE.db.profile and KE.db.profile.DungeonTimers
    if not dt then return fallback end
    local g = (mode == "text") and dt.TextGroup or dt.BarGroup
    local v = g and g.ShowAtSeconds
    -- The shared boss slider allows 0 ("always visible"), but trash alerts are
    -- pure countdowns with no spawn moment, so a 0/negative group value is
    -- meaningless here. An explicit <= 0 check is required: Lua treats 0 as
    -- truthy, so `(g and g.ShowAtSeconds) or fallback` would leak a stored 0
    -- straight into ScheduleAlert, and ShowAlert's duration<=0 guard would then
    -- silently drop every trash alert. Fall back to the per-mode floor instead.
    if not v or v <= 0 then return fallback end
    return v
end

-- Effective group default, exposed for the GUI caption + slider fallback.
function DTrash:GetSpellRevealAtDefault(mapID, npcID, spellID)
    return revealGroupDefault(mapID, npcID, spellID)
end

function DTrash:GetSpellRevealAtOverride(mapID, npcID, spellID)
    local db = profileDB()
    local t = db and db.SpellRevealOverrides
    return t and t[overrideKey(mapID, npcID, spellID)] or nil
end

-- Prune when the value equals the current group default (integer compare is
-- exact, so pruning is safe). Storing nil means "follow the group".
function DTrash:SetSpellRevealAtOverride(mapID, npcID, spellID, value)
    local t = ovTable("SpellRevealOverrides"); if not t then return end
    local key = overrideKey(mapID, npcID, spellID)
    if value == nil or value == revealGroupDefault(mapID, npcID, spellID) then
        t[key] = nil
    else
        t[key] = value
    end
end

-- Effective reveal window: override → group default. Explicit nil-check so a
-- stored value survives (never a truthy-fallback that would swallow it).
function DTrash:GetSpellRevealAt(mapID, npcID, spellID)
    local o = self:GetSpellRevealAtOverride(mapID, npcID, spellID)
    if o ~= nil then return o end
    return revealGroupDefault(mapID, npcID, spellID)
end

-- ── Time format (decimal threshold) ──────────────────────────────────────────
-- Countdown text shows one decimal below this many seconds, whole seconds at or
-- above. Flat default (trash's existing cutoff of 10; the boss editor defaults
-- to 30). No curated layer — override → default.
local DTRASH_DECIMAL_DEFAULT = 10

function DTrash:GetSpellDecimalThreshold(mapID, npcID, spellID)
    local db = profileDB()
    local t = db and db.SpellDecimalThresholds
    local o = t and t[overrideKey(mapID, npcID, spellID)]
    if o ~= nil then return o end
    return DTRASH_DECIMAL_DEFAULT
end

function DTrash:SetSpellDecimalThreshold(mapID, npcID, spellID, value)
    local t = ovTable("SpellDecimalThresholds"); if not t then return end
    local key = overrideKey(mapID, npcID, spellID)
    if value == nil or value == DTRASH_DECIMAL_DEFAULT then
        t[key] = nil
    else
        t[key] = value
    end
end

-- ── Aggregate / reset ───────────────────────────────────────────────────────

function DTrash:HasSpellOverrides(mapID, npcID, spellID)
    local db = profileDB()
    if not db then return false end
    local key = overrideKey(mapID, npcID, spellID)
    for _, name in ipairs(OVERRIDE_TABLES) do
        local t = db[name]
        if t and t[key] ~= nil then return true end
    end
    return false
end

function DTrash:ResetSpellOverrides(mapID, npcID, spellID)
    local db = profileDB()
    if not db then return end
    local key = overrideKey(mapID, npcID, spellID)
    for _, name in ipairs(OVERRIDE_TABLES) do
        local t = db[name]
        if t then t[key] = nil end
    end
end

-- Clear every trash override for one dungeon (mapID) — used by the per-dungeon
-- Reset button. Walks the dungeon's curated mobs/spells and nils each key.
function DTrash:ResetTrashOverridesForDungeon(mapID)
    local dungeon = KE.TrashData and KE.TrashData[mapID]
    if not dungeon or not dungeon.mobs then return end
    for npcID, mob in pairs(dungeon.mobs) do
        if mob.spells then
            for spellID in pairs(mob.spells) do
                self:ResetSpellOverrides(mapID, npcID, spellID)
            end
        end
    end
end

return DTrash

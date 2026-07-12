-- Tier 1: DungeonTrash per-ability override backend (TrashConfig.lua).
-- These accessors are what the dungeon Trash-section GUI drives — enable,
-- display (bar/text), color, and show-on-nameplate, each overriding a curated
-- default. The subtle bits are (a) prune-to-curated so a redundant selection
-- doesn't persist, and (b) a stored boolean `false` on the nameplate toggle
-- must read back as false, NOT as "no override" — the classic false/nil trap.
-- A regression here silently breaks a config toggle in-game with no error, so
-- pin the round-trips headlessly.

local helpers = require("dev.spec._helpers")

-- Pit of Saron / Dreadpulse Lich / Torrent of Misery — a real curated spell.
-- Shipped display default is now "text" (author default; the curation overlay
-- can pin a per-spell exception), showNameplate=true (see TrashData.lua).
local MAP, NPC, SPELL = 658, 252563, 1258820

local function loadConfig()
    local modules = helpers.installAddonShim()
    local KE = { db = { profile = { DungeonTrash = {} } } }
    helpers.loadModule("Modules/DungeonTimers/Trash/TrashData.lua", KE)
    helpers.loadModule("Modules/DungeonTimers/Trash/TrashConfig.lua", KE)
    -- Controlled EMPTY overlay so resolver tests stay independent of the shipped
    -- TrashCurated.lua content (which grows as dungeons are curated). Tests that
    -- need overlay behaviour inject KE.TrashCurated[map] themselves.
    KE.TrashCurated = {}
    return modules["DungeonTrash"], KE
end

describe("DungeonTrash config — override backend", function()
    local DT, KE
    before_each(function() DT, KE = loadConfig() end)

    it("confirms the shipped defaults (text / nameplate-on)", function()
        assert.equals("text", DT:GetSpellCuratedDisplay(MAP, NPC, SPELL))
        assert.is_true(DT:GetSpellCuratedNameplate(MAP, NPC, SPELL))
    end)

    it("curation overlay supplies shipped label/display/roles; user overrides still win", function()
        KE.TrashCurated[MAP] = { [NPC] = { [SPELL] = {
            display = "bar", label = "SOAK",
            roles = { tank = false, healer = true, dps = false },
        } } }
        assert.equals("bar", DT:GetSpellCuratedDisplay(MAP, NPC, SPELL))
        assert.equals("SOAK", DT:GetSpellCuratedLabel(MAP, NPC, SPELL))
        assert.equals("SOAK", DT:GetSpellLabel(MAP, NPC, SPELL))       -- no user override → overlay
        assert.same({ tank = false, healer = true, dps = false },      -- overlay role restriction
            DT:GetSpellCuratedRoles(MAP, NPC, SPELL))
        DT:SetSpellLabelOverride(MAP, NPC, SPELL, "INCOMING")
        assert.equals("INCOMING", DT:GetSpellLabel(MAP, NPC, SPELL))   -- user override wins
    end)

    it("colorKey pins the colour to a preset independent of the label", function()
        KE.ResolveTrashPresetColor = function(text)
            return (text == "KICK") and { 1.0, 0.15, 0.15 } or nil
        end
        KE.TrashCurated[MAP] = { [NPC] = { [SPELL] = { display = "text", colorKey = "KICK" } } }
        assert.same({ 1.0, 0.15, 0.15 }, DT:GetSpellEffectiveColor(MAP, NPC, SPELL))
        DT:SetSpellColorOverride(MAP, NPC, SPELL, { 0, 0, 1 })          -- user colour still wins
        assert.same({ 0, 0, 1 }, DT:GetSpellEffectiveColor(MAP, NPC, SPELL))
    end)

    it("round-trips the disabled flag and prunes on re-enable", function()
        assert.is_false(DT:GetSpellDisabled(MAP, NPC, SPELL))
        DT:SetSpellDisabled(MAP, NPC, SPELL, true)
        assert.is_true(DT:GetSpellDisabled(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        DT:SetSpellDisabled(MAP, NPC, SPELL, false)
        assert.is_false(DT:GetSpellDisabled(MAP, NPC, SPELL))
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))
    end)

    it("stores a display override and prunes when set back to the curated default", function()
        assert.equals("text", DT:GetSpellDisplay(MAP, NPC, SPELL))    -- curated default (text)
        DT:SetSpellDisplayOverride(MAP, NPC, SPELL, "bar")
        assert.equals("bar", DT:GetSpellDisplay(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        DT:SetSpellDisplayOverride(MAP, NPC, SPELL, "text")           -- == curated
        assert.equals("text", DT:GetSpellDisplay(MAP, NPC, SPELL))
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))        -- pruned, not stored
    end)

    it("stores a nameplate OFF override as false (not confused with no-override)", function()
        assert.is_true(DT:GetSpellShowNameplate(MAP, NPC, SPELL))     -- curated on
        DT:SetSpellNameplateOverride(MAP, NPC, SPELL, false)
        assert.is_false(DT:GetSpellShowNameplate(MAP, NPC, SPELL))    -- the false/nil trap
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        DT:SetSpellNameplateOverride(MAP, NPC, SPELL, true)           -- == curated
        assert.is_true(DT:GetSpellShowNameplate(MAP, NPC, SPELL))
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))        -- pruned
    end)

    it("cast-start sound is three-state: override > curated castSound > silent, 'None' mutes", function()
        -- No override, no curated default → silent.
        assert.is_nil(DT:GetEffectiveSpellSoundOnCastStart(MAP, NPC, SPELL))
        -- Curated default from the overlay.
        KE.TrashCurated[MAP] = { [NPC] = { [SPELL] = { castSound = "Frontal" } } }
        assert.equals("Frontal", DT:GetCuratedCastStartSound(MAP, NPC, SPELL))
        assert.equals("Frontal", DT:GetEffectiveSpellSoundOnCastStart(MAP, NPC, SPELL))
        -- The user's own pick wins.
        DT:SetSpellSoundOnCastStart(MAP, NPC, SPELL, "Kick")
        assert.equals("Kick", DT:GetEffectiveSpellSoundOnCastStart(MAP, NPC, SPELL))
        -- Explicit "None" mutes the curated default (the false/nil trap, sound flavor).
        DT:SetSpellSoundOnCastStart(MAP, NPC, SPELL, "None")
        assert.is_nil(DT:GetEffectiveSpellSoundOnCastStart(MAP, NPC, SPELL))
        -- Clearing the override falls back to the curated default.
        DT:SetSpellSoundOnCastStart(MAP, NPC, SPELL, nil)
        assert.equals("Frontal", DT:GetEffectiveSpellSoundOnCastStart(MAP, NPC, SPELL))
        -- onShow/onHide stay pure-override: no curated fallback exists for them.
        assert.is_nil(DT:GetSpellSoundOnShow(MAP, NPC, SPELL))
    end)

    it("HasSpellSound reflects effective state (curated default lights it, 'None' doesn't)", function()
        -- Nothing stored, nothing curated → no badge.
        assert.is_false(DT:HasSpellSound(MAP, NPC, SPELL))
        -- A curated castSound default alone lights the badge.
        KE.TrashCurated[MAP] = { [NPC] = { [SPELL] = { castSound = "Frontal" } } }
        assert.is_true(DT:HasSpellSound(MAP, NPC, SPELL))
        -- Muting the default with "None" turns it back off.
        DT:SetSpellSoundOnCastStart(MAP, NPC, SPELL, "None")
        assert.is_false(DT:HasSpellSound(MAP, NPC, SPELL))
        -- A stored "None" on onShow doesn't count either; a real pick does.
        DT:SetSpellSoundOnShow(MAP, NPC, SPELL, "None")
        assert.is_false(DT:HasSpellSound(MAP, NPC, SPELL))
        DT:SetSpellSoundOnShow(MAP, NPC, SPELL, "Kick")
        assert.is_true(DT:HasSpellSound(MAP, NPC, SPELL))
    end)

    it("round-trips a color override and falls back to the default when cleared", function()
        assert.is_nil(DT:GetSpellColorOverride(MAP, NPC, SPELL))
        assert.same({ 0.3, 0.5, 0.9 }, DT:GetSpellEffectiveColor(MAP, NPC, SPELL))
        DT:SetSpellColorOverride(MAP, NPC, SPELL, { 1, 0, 0 })
        assert.same({ 1, 0, 0 }, DT:GetSpellColorOverride(MAP, NPC, SPELL))
        assert.same({ 1, 0, 0 }, DT:GetSpellEffectiveColor(MAP, NPC, SPELL))
        DT:SetSpellColorOverride(MAP, NPC, SPELL, nil)
        assert.is_nil(DT:GetSpellColorOverride(MAP, NPC, SPELL))
        assert.same({ 0.3, 0.5, 0.9 }, DT:GetSpellEffectiveColor(MAP, NPC, SPELL))
    end)

    it("ResetSpellOverrides clears every table for one spell", function()
        DT:SetSpellDisabled(MAP, NPC, SPELL, true)
        DT:SetSpellDisplayOverride(MAP, NPC, SPELL, "text")
        DT:SetSpellNameplateOverride(MAP, NPC, SPELL, false)
        DT:SetSpellColorOverride(MAP, NPC, SPELL, { 1, 0, 0 })
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        DT:ResetSpellOverrides(MAP, NPC, SPELL)
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))
    end)

    it("ResetTrashOverridesForDungeon clears every mob/spell in the map", function()
        -- second curated spell in the same dungeon (Glacieth / Cryoburst)
        local NPC2, SPELL2 = 252564, 1259188
        DT:SetSpellDisabled(MAP, NPC, SPELL, true)
        DT:SetSpellDisplayOverride(MAP, NPC2, SPELL2, "bar")  -- differs from the "text" default
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellOverrides(MAP, NPC2, SPELL2))
        DT:ResetTrashOverridesForDungeon(MAP)
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))
        assert.is_false(DT:HasSpellOverrides(MAP, NPC2, SPELL2))
    end)

    it("TrashDungeonByKey resolves a dungeonKey to its data entry", function()
        local d = DT:TrashDungeonByKey("PitOfSaron")
        assert.is_table(d)
        assert.equals(MAP, d.mapID)
        assert.is_nil(DT:TrashDungeonByKey("NoSuchDungeon"))
    end)
end)

-- Role filter ("who sees it") — the Visibility-tab Tank/Healer/DPS toggles and
-- the runtime gate that suppresses an alert the player's role shouldn't see.
-- Ymirjar Graveblade / Frostbane Slash is a curated tank+healer-only spell
-- (dps=false), so it exercises a non-all-roles default.
local NPC_DPSOFF, SPELL_DPSOFF = 252610, 1258439

describe("DungeonTrash config — role filter", function()
    local DT
    before_each(function() DT = loadConfig() end)
    after_each(function() _G.UnitGroupRolesAssigned = nil end)

    it("reads curated role sets (all-roles vs a dps-excluded spell)", function()
        assert.same({ tank = true, healer = true, dps = true },
            DT:GetSpellCuratedRoles(MAP, NPC, SPELL))
        local r = DT:GetSpellCuratedRoles(MAP, NPC_DPSOFF, SPELL_DPSOFF)
        assert.is_true(r.tank)
        assert.is_true(r.healer)
        assert.is_false(r.dps)
    end)

    it("effective roles mirror curated until an override is set", function()
        assert.same(DT:GetSpellCuratedRoles(MAP, NPC, SPELL),
            DT:GetSpellEffectiveRoles(MAP, NPC, SPELL))
    end)

    it("toggling one role preserves the others and prunes back to curated", function()
        DT:SetSpellRoleOverride(MAP, NPC, SPELL, "dps", false)
        local r = DT:GetSpellEffectiveRoles(MAP, NPC, SPELL)
        assert.is_true(r.tank)      -- untouched
        assert.is_true(r.healer)    -- untouched
        assert.is_false(r.dps)      -- flipped
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        DT:SetSpellRoleOverride(MAP, NPC, SPELL, "dps", true)   -- == curated
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))  -- pruned
    end)

    it("PlayerSeesTrashSpell gates on the player's assigned role", function()
        _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
        assert.is_true(DT:PlayerSeesTrashSpell(MAP, NPC, SPELL))          -- dps allowed
        assert.is_false(DT:PlayerSeesTrashSpell(MAP, NPC_DPSOFF, SPELL_DPSOFF)) -- dps excluded
        _G.UnitGroupRolesAssigned = function() return "TANK" end
        assert.is_true(DT:PlayerSeesTrashSpell(MAP, NPC_DPSOFF, SPELL_DPSOFF))  -- tank allowed
    end)

    it("PlayerSeesTrashSpell fails open on an unknown/nil role", function()
        _G.UnitGroupRolesAssigned = function() return "NONE" end
        assert.is_true(DT:PlayerSeesTrashSpell(MAP, NPC_DPSOFF, SPELL_DPSOFF))
        _G.UnitGroupRolesAssigned = function() return nil end
        assert.is_true(DT:PlayerSeesTrashSpell(MAP, NPC_DPSOFF, SPELL_DPSOFF))
    end)
end)

-- Sounds (Actions tab) — onShow/onHide are stored under one entry; either may be
-- nil and the entry prunes only when both are gone.
describe("DungeonTrash config — sound overrides", function()
    local DT
    before_each(function() DT = loadConfig() end)

    it("has no sound by default", function()
        assert.is_nil(DT:GetSpellSoundOnShow(MAP, NPC, SPELL))
        assert.is_nil(DT:GetSpellSoundOnHide(MAP, NPC, SPELL))
        assert.is_false(DT:HasSpellSound(MAP, NPC, SPELL))
    end)

    it("round-trips onShow and onHide independently", function()
        DT:SetSpellSoundOnShow(MAP, NPC, SPELL, "Alarm")
        assert.equals("Alarm", DT:GetSpellSoundOnShow(MAP, NPC, SPELL))
        assert.is_nil(DT:GetSpellSoundOnHide(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellSound(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        DT:SetSpellSoundOnHide(MAP, NPC, SPELL, "Chime")
        assert.equals("Alarm", DT:GetSpellSoundOnShow(MAP, NPC, SPELL))  -- preserved
        assert.equals("Chime", DT:GetSpellSoundOnHide(MAP, NPC, SPELL))
    end)

    it("clearing both sounds prunes the entry; empty string counts as clear", function()
        DT:SetSpellSoundOnShow(MAP, NPC, SPELL, "Alarm")
        DT:SetSpellSoundOnHide(MAP, NPC, SPELL, "Chime")
        DT:SetSpellSoundOnShow(MAP, NPC, SPELL, nil)
        assert.is_true(DT:HasSpellSound(MAP, NPC, SPELL))               -- onHide remains
        DT:SetSpellSoundOnHide(MAP, NPC, SPELL, "")                     -- "" == clear
        assert.is_false(DT:HasSpellSound(MAP, NPC, SPELL))
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))          -- pruned
    end)

    -- Third slot (2026-07-10): the observed cast-start cue — same entry, same
    -- prune rule, independent of the two prediction-fired slots.
    it("round-trips onCastStart and keeps the entry alive on its own", function()
        assert.is_nil(DT:GetSpellSoundOnCastStart(MAP, NPC, SPELL))
        DT:SetSpellSoundOnCastStart(MAP, NPC, SPELL, "Kick")
        assert.equals("Kick", DT:GetSpellSoundOnCastStart(MAP, NPC, SPELL))
        assert.is_nil(DT:GetSpellSoundOnShow(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellSound(MAP, NPC, SPELL))
        DT:SetSpellSoundOnCastStart(MAP, NPC, SPELL, nil)
        assert.is_false(DT:HasSpellSound(MAP, NPC, SPELL))              -- pruned again
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))
    end)
end)

-- Custom label (Display tab text + preset chips write here).
describe("DungeonTrash config — label override", function()
    local DT
    before_each(function() DT = loadConfig() end)

    it("reads the curated spell name as the default label", function()
        assert.equals("Torrent of Misery", DT:GetSpellCuratedLabel(MAP, NPC, SPELL))
        assert.equals("Torrent of Misery", DT:GetSpellLabel(MAP, NPC, SPELL))
    end)

    it("exposes the raw override (nil when unset) for the editbox binding", function()
        assert.is_nil(DT:GetSpellLabelOverride(MAP, NPC, SPELL))       -- unset → empty field
        DT:SetSpellLabelOverride(MAP, NPC, SPELL, "INCOMING")
        assert.equals("INCOMING", DT:GetSpellLabelOverride(MAP, NPC, SPELL))
        DT:SetSpellLabelOverride(MAP, NPC, SPELL, "Torrent of Misery") -- == curated → pruned
        assert.is_nil(DT:GetSpellLabelOverride(MAP, NPC, SPELL))
    end)

    it("round-trips a custom label and prunes on blank or curated", function()
        DT:SetSpellLabelOverride(MAP, NPC, SPELL, "INCOMING")
        assert.equals("INCOMING", DT:GetSpellLabel(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        DT:SetSpellLabelOverride(MAP, NPC, SPELL, "Torrent of Misery")  -- == curated
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))          -- pruned
        DT:SetSpellLabelOverride(MAP, NPC, SPELL, "INCOMING")
        DT:SetSpellLabelOverride(MAP, NPC, SPELL, "")                   -- blank clears
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))
        assert.equals("Torrent of Misery", DT:GetSpellLabel(MAP, NPC, SPELL))
    end)
end)

-- Reveal window (lead time) — the Visibility-tab "Reveal at (s before cast)"
-- slider. Trash has no curated reveal; the effective default is the shared
-- DungeonTimers group ShowAtSeconds, so the test wires that up.
describe("DungeonTrash config — reveal window (lead time)", function()
    local DT, KE
    before_each(function()
        DT, KE = loadConfig()
        KE.db.profile.DungeonTimers = {
            BarGroup = { ShowAtSeconds = 8 },
            TextGroup = { ShowAtSeconds = 8 },
        }
    end)

    it("defaults to the shared group ShowAtSeconds when unset", function()
        assert.equals(8, DT:GetSpellRevealAtDefault(MAP, NPC, SPELL))
        assert.is_nil(DT:GetSpellRevealAtOverride(MAP, NPC, SPELL))
        assert.equals(8, DT:GetSpellRevealAt(MAP, NPC, SPELL))
    end)

    it("round-trips an override and prunes when set back to the group default", function()
        DT:SetSpellRevealAtOverride(MAP, NPC, SPELL, 5)
        assert.equals(5, DT:GetSpellRevealAt(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        DT:SetSpellRevealAtOverride(MAP, NPC, SPELL, 8)   -- == group default
        assert.is_nil(DT:GetSpellRevealAtOverride(MAP, NPC, SPELL))
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))
        assert.equals(8, DT:GetSpellRevealAt(MAP, NPC, SPELL))
    end)

    it("preserves a stored 0 (nil-check, not a truthy fallback)", function()
        DT:SetSpellRevealAtOverride(MAP, NPC, SPELL, 0)
        assert.equals(0, DT:GetSpellRevealAtOverride(MAP, NPC, SPELL))
        assert.equals(0, DT:GetSpellRevealAt(MAP, NPC, SPELL))
    end)

    -- Regression (2026-07-06 review): the shared boss "Reveal at" slider allows
    -- 0 ("always visible"), but 0 is meaningless for a trash countdown — it would
    -- reach ShowAlert as duration<=0 and be silently dropped, killing every
    -- trash alert. The group default must floor a 0/negative to the per-mode
    -- trash fallback (text 5 / bar 10) rather than leak a truthy 0.
    it("floors a shared group ShowAtSeconds of 0 to the per-mode trash floor", function()
        KE.db.profile.DungeonTimers.BarGroup.ShowAtSeconds = 0
        KE.db.profile.DungeonTimers.TextGroup.ShowAtSeconds = 0
        -- SPELL (Torrent of Misery) resolves to text mode -> 5s floor.
        assert.equals(5, DT:GetSpellRevealAtDefault(MAP, NPC, SPELL))
        assert.equals(5, DT:GetSpellRevealAt(MAP, NPC, SPELL))
        -- Bar-mode alerts floor to 10s.
        DT:SetSpellDisplayOverride(MAP, NPC, SPELL, "bar")
        assert.equals(10, DT:GetSpellRevealAtDefault(MAP, NPC, SPELL))
        assert.equals(10, DT:GetSpellRevealAt(MAP, NPC, SPELL))
    end)
end)

-- Decimal threshold (Time Format) — countdown shows one decimal below N seconds,
-- whole seconds at/above. Flat default 10 (trash's existing cutoff).
describe("DungeonTrash config — decimal threshold (time format)", function()
    local DT
    before_each(function() DT = loadConfig() end)

    it("defaults to 10 when unset", function()
        assert.equals(10, DT:GetSpellDecimalThreshold(MAP, NPC, SPELL))
    end)

    it("round-trips an override and prunes at the default", function()
        DT:SetSpellDecimalThreshold(MAP, NPC, SPELL, 20)
        assert.equals(20, DT:GetSpellDecimalThreshold(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
        DT:SetSpellDecimalThreshold(MAP, NPC, SPELL, 10)  -- == default
        assert.is_false(DT:HasSpellOverrides(MAP, NPC, SPELL))
        assert.equals(10, DT:GetSpellDecimalThreshold(MAP, NPC, SPELL))
    end)

    it("preserves a stored 0 (always whole seconds)", function()
        DT:SetSpellDecimalThreshold(MAP, NPC, SPELL, 0)
        assert.equals(0, DT:GetSpellDecimalThreshold(MAP, NPC, SPELL))
        assert.is_true(DT:HasSpellOverrides(MAP, NPC, SPELL))
    end)
end)

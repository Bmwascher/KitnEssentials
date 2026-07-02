-- Tier 1+2: DungeonTimers curated data + display-preset resolution.
-- EncounterData.lua is hand-curated per patch and a schema typo fails
-- SILENTLY in-game: a bad castType/role is never read back, a dangling
-- phantomFollowupOf never spawns, an unknown displayText quietly falls back
-- to the default bar color. The lint half walks every spell entry against
-- the schema documented at EncounterData.lua:6-344; the resolution half
-- drives the REAL (file-local) ResolveDisplayPreset through DT:CreateBar
-- and the exposed DT._ResolvePresetByText.
-- Sound keys (spell/phase sound + soundOnHide) are deliberately NOT
-- validated — approved decision (would need the LSM sound list from
-- Core/Globals.lua).
local L = require("dev.spec._ke_loader")

-- Schema enums, EncounterData.lua:13-25. castType is curation metadata
-- (never read by DungeonTimers.lua) but the schema requires it on every
-- cast-driven entry; spawnOnMessage / phantomFollowupOf entries opt out of
-- the BigWigs_Timer path and are exempt.
local CAST_TYPES = { begincast = true, cast = true, channel = true }
local ROLES = { tank = true, heal = true, mechanic = true, other = true, kick = true, move = true }
local DISPLAYS = { bar = true, text = true }

-- Labels that deliberately render with DEFAULT_BAR_COLOR (no preset, no
-- alias, no curated color). Anything else unresolvable is treated as a typo.
local DEFAULT_COLOR_LABELS = { ["BOSS BUFFED"] = true, ["KICK"] = true }

describe("DungeonTimers EncounterData — curated-data lint", function()
    local DT, KE

    setup(function()
        DT, KE = L.loadDungeonTimers({ withEncounterData = true })
    end)

    -- One failure string per violation so a bad entry reports its
    -- encounter+spellId instead of aborting the walk opaquely.
    local function forEachSpell(fn)
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            for spellId, spell in pairs(type(enc.spells) == "table" and enc.spells or {}) do
                local ctx = string.format("enc %s (%s) spell %s",
                    tostring(encId), tostring(enc.name), tostring(spellId))
                fn(failures, ctx, enc, spellId, spell)
            end
        end
        return failures
    end

    local function isPositiveNumber(v)
        return type(v) == "number" and v > 0
    end

    -- True when the label reaches a curated color through ResolvePresetByText
    -- (key or label match) or the color-only alias table.
    local function resolvesToPreset(text)
        return DT._ResolvePresetByText(text) ~= nil
            or DT.DISPLAY_PRESET_ALIASES[text:upper()] ~= nil
    end

    local function lintColor(failures, ctx, site, c)
        if c == nil then return end
        if type(c) ~= "table" or #c ~= 3 then
            failures[#failures + 1] = ctx .. ": " .. site .. " must be a {r,g,b} triple"
            return
        end
        for i = 1, 3 do
            if type(c[i]) ~= "number" or c[i] < 0 or c[i] > 1 then
                failures[#failures + 1] = string.format("%s: %s[%d] out of 0..1", ctx, site, i)
            end
        end
    end

    -- displayText contract: resolve to a preset/alias color, or carry an
    -- explicit curated color, or be a known deliberate default-color label.
    -- Catches the silent fall-back-to-DEFAULT_BAR_COLOR typo class
    -- (ResolveDisplayPreset, DungeonTimers.lua:246-255).
    local function lintLabel(failures, ctx, site, text, hasExplicitColor)
        if text == nil then return end
        if type(text) ~= "string" or text == "" then
            failures[#failures + 1] = ctx .. ": " .. site .. " must be a non-empty string"
            return
        end
        if resolvesToPreset(text) then return end
        if hasExplicitColor then return end
        if DEFAULT_COLOR_LABELS[text:upper()] then return end
        failures[#failures + 1] = ctx .. ": " .. site .. " '" .. text ..
            "' resolves to no preset/alias and carries no curated color"
    end

    it("loads a non-empty curated table", function()
        local encs, spells, rules = 0, 0, 0
        for _, enc in pairs(KE.EncounterData) do
            encs = encs + 1
            for _ in pairs(enc.spells or {}) do spells = spells + 1 end
            for _ in ipairs(enc.phases or {}) do rules = rules + 1 end
        end
        assert.is_true(encs > 0)
        assert.is_true(spells > encs)   -- every boss curates several spells
        assert.is_true(rules > 0)
    end)

    it("encounter shells carry name, dungeon and a spells table", function()
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            local ctx = "enc " .. tostring(encId)
            if type(enc.name) ~= "string" or enc.name == "" then
                failures[#failures + 1] = ctx .. ": name must be a non-empty string"
            end
            if type(enc.dungeon) ~= "string" or enc.dungeon == "" then
                failures[#failures + 1] = ctx .. ": dungeon must be a non-empty string"
            end
            if type(enc.spells) ~= "table" or next(enc.spells) == nil then
                failures[#failures + 1] = ctx .. ": spells must be a non-empty table"
            end
            if enc.bossOrder ~= nil and not isPositiveNumber(enc.bossOrder) then
                failures[#failures + 1] = ctx .. ": bossOrder must be a positive number"
            end
            -- BigWigs_Timer lookup runs through tonumber(spellId) and indexes
            -- by number (DungeonTimers.lua:3265) — a string key never matches.
            for spellId in pairs(type(enc.spells) == "table" and enc.spells or {}) do
                if type(spellId) ~= "number" then
                    failures[#failures + 1] = ctx .. ": spell key " .. tostring(spellId) ..
                        " must be a numeric spellID"
                end
            end
        end
        assert.same({}, failures)
    end)

    it("every spell entry has a valid trigger classification", function()
        local failures = forEachSpell(function(failures, ctx, _, _, spell)
            if spell.castType ~= nil then
                if not CAST_TYPES[spell.castType] then
                    failures[#failures + 1] = ctx .. ": unknown castType '" .. tostring(spell.castType) .. "'"
                end
            elseif not (spell.spawnOnMessage or spell.phantomFollowupOf) then
                failures[#failures + 1] = ctx ..
                    ": no castType and no alternate trigger (spawnOnMessage/phantomFollowupOf)"
            end
            -- Alternate-trigger entries skip the BigWigs_Timer path and spawn
            -- from `duration`; the spawn helpers drop duration <= 0, so a
            -- missing duration is a dead entry (DungeonTimers.lua:2003/:2061).
            if spell.spawnOnMessage or spell.phantomFollowupOf then
                if not isPositiveNumber(spell.duration) then
                    failures[#failures + 1] = ctx .. ": alternate-trigger entry needs a positive duration"
                end
            end
            if spell.leadDelay ~= nil and (type(spell.leadDelay) ~= "number" or spell.leadDelay < 0) then
                failures[#failures + 1] = ctx .. ": leadDelay must be a number >= 0"
            end
        end)
        assert.same({}, failures)
    end)

    it("identity, enums and flags are valid", function()
        local failures = forEachSpell(function(failures, ctx, _, _, spell)
            if type(spell.name) ~= "string" or spell.name == "" then
                failures[#failures + 1] = ctx .. ": name must be a non-empty string"
            end
            if spell.role ~= nil and not ROLES[spell.role] then
                failures[#failures + 1] = ctx .. ": unknown role '" .. tostring(spell.role) .. "'"
            end
            if spell.display ~= nil and not DISPLAYS[spell.display] then
                failures[#failures + 1] = ctx .. ": unknown display '" .. tostring(spell.display) .. "'"
            end
            for _, flag in ipairs({ "disabled", "sortAtEnd", "extendByChannel", "spawnOnMessage" }) do
                if spell[flag] ~= nil and type(spell[flag]) ~= "boolean" then
                    failures[#failures + 1] = ctx .. ": " .. flag .. " must be boolean"
                end
            end
            local sec = spell.secondary
            if sec ~= nil then
                if type(sec) ~= "table" then
                    failures[#failures + 1] = ctx .. ": secondary must be a table"
                else
                    if sec.role ~= nil and not ROLES[sec.role] then
                        failures[#failures + 1] = ctx .. ": unknown secondary.role '" .. tostring(sec.role) .. "'"
                    end
                    if sec.display ~= nil and not DISPLAYS[sec.display] then
                        failures[#failures + 1] = ctx .. ": unknown secondary.display '" .. tostring(sec.display) .. "'"
                    end
                end
            end
        end)
        assert.same({}, failures)
    end)

    it("duration fields are positive numbers (channels carry channelDuration)", function()
        local failures = forEachSpell(function(failures, ctx, _, _, spell)
            for _, field in ipairs({ "castDuration", "channelDuration", "forceDuration", "duration" }) do
                if spell[field] ~= nil and not isPositiveNumber(spell[field]) then
                    failures[#failures + 1] = ctx .. ": " .. field .. " must be a positive number"
                end
            end
            -- showAtSeconds = 0 is meaningful ("force always visible",
            -- EncounterData.lua:85-87), so 0 is allowed here.
            if spell.showAtSeconds ~= nil
                and (type(spell.showAtSeconds) ~= "number" or spell.showAtSeconds < 0) then
                failures[#failures + 1] = ctx .. ": showAtSeconds must be a number >= 0"
            end
            if spell.castType == "channel" and not isPositiveNumber(spell.channelDuration) then
                failures[#failures + 1] = ctx .. ": channel castType requires channelDuration"
            end
            -- extendByChannel without channelDuration is a silent no-op in
            -- GetSpellExtension (DungeonTimers.lua:367) — curator error.
            if spell.extendByChannel and not isPositiveNumber(spell.channelDuration) then
                failures[#failures + 1] = ctx .. ": extendByChannel requires channelDuration"
            end
        end)
        assert.same({}, failures)
    end)

    it("postCastBar / shieldBar / iconOverride configs are well-formed", function()
        local failures = forEachSpell(function(failures, ctx, _, _, spell)
            local pcb = spell.postCastBar
            if pcb ~= nil then
                if type(pcb) ~= "table" then
                    failures[#failures + 1] = ctx .. ": postCastBar must be a table"
                else
                    -- RenderBar drops baseDur <= 0 (DungeonTimers.lua:1919):
                    -- a postCastBar without a positive duration never renders.
                    if not isPositiveNumber(pcb.duration) then
                        failures[#failures + 1] = ctx .. ": postCastBar.duration must be a positive number"
                    end
                    if pcb.display ~= nil and not DISPLAYS[pcb.display] then
                        failures[#failures + 1] = ctx .. ": unknown postCastBar.display '" .. tostring(pcb.display) .. "'"
                    end
                    if pcb.iconOverride ~= nil and type(pcb.iconOverride) ~= "number" and type(pcb.iconOverride) ~= "string" then
                        failures[#failures + 1] = ctx .. ": postCastBar.iconOverride must be a texture ID or path"
                    end
                end
            end
            local sb = spell.shieldBar
            if sb ~= nil then
                if type(sb) ~= "table" then
                    failures[#failures + 1] = ctx .. ": shieldBar must be a table"
                else
                    if not isPositiveNumber(sb.baseAmount) then
                        failures[#failures + 1] = ctx .. ": shieldBar.baseAmount must be a positive number"
                    end
                    if sb.displayText ~= nil and (type(sb.displayText) ~= "string" or sb.displayText == "") then
                        failures[#failures + 1] = ctx .. ": shieldBar.displayText must be a non-empty string"
                    end
                end
            end
            if spell.iconOverride ~= nil and type(spell.iconOverride) ~= "number" and type(spell.iconOverride) ~= "string" then
                failures[#failures + 1] = ctx .. ": iconOverride must be a texture ID or path"
            end
        end)
        assert.same({}, failures)
    end)

    it("color arrays are three numbers in 0..1", function()
        local failures = forEachSpell(function(failures, ctx, _, _, spell)
            lintColor(failures, ctx, "color", spell.color)
            if type(spell.secondary) == "table" then
                lintColor(failures, ctx, "secondary.color", spell.secondary.color)
            end
        end)
        assert.same({}, failures)
    end)

    it("phantomFollowupOf resolves to a different spell in the same encounter", function()
        local failures = forEachSpell(function(failures, ctx, enc, spellId, spell)
            if spell.phantomFollowupOf == nil then return end
            -- GetSpellPhantomFollowupOf goes through tonumber (DungeonTimers.lua:592).
            local parent = tonumber(spell.phantomFollowupOf)
            if not parent then
                failures[#failures + 1] = ctx .. ": phantomFollowupOf is not numeric"
            elseif parent == spellId then
                failures[#failures + 1] = ctx .. ": phantomFollowupOf points at itself"
            elseif enc.spells[parent] == nil then
                -- Phantoms spawn off the PARENT's BigWigs_Timer during the same
                -- encounter — a cross-encounter or unknown parent never fires.
                failures[#failures + 1] = ctx .. ": phantomFollowupOf " .. tostring(parent) ..
                    " has no sibling entry in this encounter"
            end
        end)
        assert.same({}, failures)
    end)

    it("every curated label resolves to a preset/alias color or carries its own", function()
        local failures = forEachSpell(function(failures, ctx, _, _, spell)
            local hasColor = spell.color ~= nil
            lintLabel(failures, ctx, "displayText", spell.displayText, hasColor)
            -- castDisplayText exists to swap label AND color at cast start
            -- (EncounterData.lua:35-46); there is no per-cast color field, so
            -- it must resolve — the StopBar swap reads castColor, which is
            -- preset-derived only (DungeonTimers.lua:2119).
            lintLabel(failures, ctx, "castDisplayText", spell.castDisplayText, false)
            if type(spell.secondary) == "table" then
                lintLabel(failures, ctx, "secondary.displayText",
                    spell.secondary.displayText, spell.secondary.color ~= nil)
            end
            if type(spell.postCastBar) == "table" then
                -- postCastBar inherits the parent's spellId, so the parent's
                -- curated color is its explicit-color escape.
                lintLabel(failures, ctx, "postCastBar.displayText",
                    spell.postCastBar.displayText, hasColor)
            end
            -- shieldBar.displayText is exempt from color resolution — the
            -- shield bar's fill color is hardcoded (DungeonTimers.lua:2679).
        end)
        assert.same({}, failures)
    end)

    it("phase rules are well-formed", function()
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            if enc.phases ~= nil then
                if type(enc.phases) ~= "table" then
                    failures[#failures + 1] = "enc " .. tostring(encId) .. ": phases must be a table"
                else
                    for i, rule in ipairs(enc.phases) do
                        local ctx = string.format("enc %s (%s) phase %d",
                            tostring(encId), tostring(enc.name), i)
                        -- unit defaults to boss1 (RefreshPhaseBars); if given it
                        -- must be a bossN token.
                        if rule.unit ~= nil and not (type(rule.unit) == "string" and rule.unit:match("^boss%d$")) then
                            failures[#failures + 1] = ctx .. ": unit must be a 'bossN' token"
                        end
                        if type(rule.threshold) ~= "number" or rule.threshold <= 0 or rule.threshold >= 100 then
                            failures[#failures + 1] = ctx .. ": threshold must be a number in (0, 100)"
                        end
                        -- BuildPhase*Curve all bail on lead <= 0
                        -- (DungeonTimers.lua:2430) — a non-positive curated
                        -- lead is a dead rule.
                        if not isPositiveNumber(rule.lead) then
                            failures[#failures + 1] = ctx .. ": lead must be a positive number"
                        end
                    end
                end
            end
        end
        assert.same({}, failures)
    end)

    it("preset and alias tables are internally consistent", function()
        local failures = {}
        for key, preset in pairs(DT.DISPLAY_PRESETS) do
            -- ResolvePresetByText indexes DISPLAY_PRESETS[str:upper()]
            -- (DungeonTimers.lua:237): a non-uppercase key is unreachable by key.
            if key ~= key:upper() then
                failures[#failures + 1] = "preset '" .. key .. "': key must be uppercase"
            end
            if type(preset.label) ~= "string" or preset.label == "" then
                failures[#failures + 1] = "preset '" .. key .. "': label must be a non-empty string"
            end
            if preset.color == nil then
                failures[#failures + 1] = "preset '" .. key .. "': missing color"
            end
            lintColor(failures, "preset '" .. key .. "'", "color", preset.color)
        end
        for aliasKey, target in pairs(DT.DISPLAY_PRESET_ALIASES) do
            -- Alias lookup upper-cases the INPUT only (DungeonTimers.lua:250);
            -- a non-uppercase alias key never matches.
            if aliasKey ~= aliasKey:upper() then
                failures[#failures + 1] = "alias '" .. aliasKey .. "': key must be uppercase"
            end
            -- A dangling alias silently falls through to the default color
            -- (guard at DungeonTimers.lua:251).
            if DT.DISPLAY_PRESETS[target] == nil then
                failures[#failures + 1] = "alias '" .. tostring(aliasKey) .. "': target '" ..
                    tostring(target) .. "' is not a preset"
            end
        end
        assert.same({}, failures)
    end)
end)

-- Local CreateFrame stub for the CreateBar path: _wow_mock's catch-all
-- __index frame resolves EVERY key to a function, so CreateBar's create-once
-- gates (`if not frame.bar then`) and field reads that must start nil
-- (frame.icon, frame.timerText, ...) never do. Plain tables with explicit
-- no-op methods keep unassigned fields nil.
local FRAME_METHODS = {
    "Show", "Hide", "SetShown", "SetSize", "SetPoint", "SetAllPoints",
    "ClearAllPoints", "SetScript", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetMinMaxValues", "SetValue",
    "SetStatusBarTexture", "SetStatusBarColor", "SetFont", "SetText",
    "SetTextColor", "SetJustifyH", "SetAlpha", "SetTexture",
}
local function newPlainStubFrame()
    local f = {}
    for _, m in ipairs(FRAME_METHODS) do f[m] = function() end end
    f.IsShown = function() return false end
    f.CreateFontString = function() return newPlainStubFrame() end
    f.CreateTexture = function() return newPlainStubFrame() end
    return f
end

-- ResolveDisplayPreset is a file-local; DT:CreateBar is its observable seam
-- (frame.baseText / frame.barColor / frame.castBaseText / frame.castColor).
-- Color assertions use table IDENTITY (assert.equals) against the live
-- DT.DISPLAY_PRESETS entries — proves the color is borrowed, not copied.
describe("DungeonTimers display-preset resolution", function()
    local DT

    before_each(function()
        DT = L.loadDungeonTimers({ withEncounterData = true },
            { CreateFrame = function() return newPlainStubFrame() end })
    end)

    it("_ResolvePresetByText matches keys and labels case-insensitively, aliases not at all", function()
        assert.equals(DT.DISPLAY_PRESETS.AOE, DT._ResolvePresetByText("aoe"))
        assert.equals(DT.DISPLAY_PRESETS.TANK, DT._ResolvePresetByText("Tank Hit"))  -- label match
        assert.is_nil(DT._ResolvePresetByText(nil))
        assert.is_nil(DT._ResolvePresetByText("KNOCK"))  -- aliases are color-only, not presets
        assert.is_nil(DT._ResolvePresetByText("NO SUCH"))
    end)

    it("matches a preset key case-insensitively and canonicalizes the label", function()
        local bar = DT:CreateBar("k1", 5, 0, "bar", "dodge")
        assert.equals("DODGE", bar.baseText)
        assert.equals(DT.DISPLAY_PRESETS.DODGE.color, bar.barColor)
    end)

    it("matches by preset label when the key differs (tank hit → TANK)", function()
        local bar = DT:CreateBar("k2", 5, 0, "bar", "tank hit")
        assert.equals("TANK HIT", bar.baseText)
        assert.equals(DT.DISPLAY_PRESETS.TANK.color, bar.barColor)
    end)

    it("alias borrows the target preset's color but keeps the curator's text", function()
        local bar = DT:CreateBar("k3", 5, 0, "bar", "Knock")
        assert.equals("Knock", bar.baseText)  -- original casing preserved
        assert.equals(DT.DISPLAY_PRESETS.PULL.color, bar.barColor)
    end)

    it("unknown text keeps the text and falls back to the default bar color", function()
        local bar = DT:CreateBar("k4", 5, 0, "bar", "TOTALLY CUSTOM")
        assert.equals("TOTALLY CUSTOM", bar.baseText)
        assert.same({ 0.3, 0.5, 0.9 }, bar.barColor)  -- DEFAULT_BAR_COLOR (DungeonTimers.lua:187)
    end)

    it("nil displayText falls back to the BigWigs text with the ' (N)' counter stripped", function()
        local bar = DT:CreateBar("Fireball (2)", 5, 0, "bar", nil)
        assert.equals("Fireball", bar.baseText)
        -- Strip is end-anchored (StripBigWigsCounter, DungeonTimers.lua:302).
        local bar2 = DT:CreateBar("(2) Fireball", 5, 0, "bar", nil)
        assert.equals("(2) Fireball", bar2.baseText)
    end)

    it("castDisplayText resolves through the same preset path", function()
        local bar = DT:CreateBar("k5", 5, 2, "bar", "CC ADDS", nil, "aoe")
        assert.equals("AOE", bar.castBaseText)
        assert.equals(DT.DISPLAY_PRESETS.AOE.color, bar.castColor)
        -- Alias in the cast slot: text preserved, color borrowed.
        local bar2 = DT:CreateBar("k6", 5, 2, "bar", "CC ADDS", nil, "Knock")
        assert.equals("Knock", bar2.castBaseText)
        assert.equals(DT.DISPLAY_PRESETS.PULL.color, bar2.castColor)
    end)
end)

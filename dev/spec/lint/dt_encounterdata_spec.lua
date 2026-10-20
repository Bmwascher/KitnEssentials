-- Tier 1+2: DungeonTimers curated data + display-preset resolution.
-- EncounterData.lua is hand-curated per patch and a schema typo fails
-- SILENTLY in-game: a bad castType/role is never read back, a dangling
-- phantomFollowupOf never spawns, an unknown displayText quietly falls back
-- to the default bar color. The lint half walks every spell entry against
-- the schema documented at EncounterData.lua; the resolution half
-- drives the REAL (file-local) ResolveDisplayPreset through DT:CreateBar
-- and the exposed DT._ResolvePresetByText.
-- Curated spell, cue, phase and aura sound names are checked against the
-- registered list and the shipped files: an unresolved name plays nothing.
local L = require("dev.spec._ke_loader")

-- Schema enums, EncounterData.lua. castType is curation metadata
-- (never read by DungeonTimers.lua) but the schema requires it on every
-- cast-driven entry; spawnOnMessage / phantomFollowupOf entries opt out of
-- the BigWigs_Timer path and are exempt.
local CAST_TYPES = { begincast = true, cast = true, channel = true }
local ROLES = { tank = true, heal = true, mechanic = true, other = true, kick = true, move = true }
local DISPLAYS = { bar = true, text = true }

-- Labels that deliberately render with DEFAULT_BAR_COLOR (no preset, no
-- alias, no curated color). Anything else unresolvable is treated as a typo.
local DEFAULT_COLOR_LABELS = { ["BOSS BUFFED"] = true, ["BOSS LEAP"] = true, ["KICK"] = true }

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
    -- (ResolveDisplayPreset, DungeonTimers.lua).
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
            -- by number (DungeonTimers.lua) — a string key never matches.
            for spellId in pairs(type(enc.spells) == "table" and enc.spells or {}) do
                if type(spellId) ~= "number" then
                    failures[#failures + 1] = ctx .. ": spell key " .. tostring(spellId) ..
                        " must be a numeric spellID"
                end
            end
        end
        assert.same({}, failures)
    end)

    -- The wind map reads both rows through their explicit anchored bindings,
    -- whose owned hold and estimate end bound each card's lifetime.
    it("a windMap names anchored explicit Timer rows of its own encounter", function()
        local bindings = KE._DungeonTimerState.BuildBindings(KE.EncounterData)
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            if enc.windMap ~= nil then
                local timers = bindings.timers[encId] or {}
                for _, field in ipairs({ "wind", "spit" }) do
                    local id = type(enc.windMap) == "table" and enc.windMap[field] or nil
                    local binding = id and timers[id]
                    if not (binding and binding.policy == "estimated-impact"
                        and binding.anchor == "timeline-finished") then
                        failures[#failures + 1] = "enc " .. tostring(encId) .. ": windMap." .. field ..
                            " must name an anchored explicit Timer row"
                    end
                end
            end
        end
        assert.same({}, failures)
    end)

    -- The settings page places each named row once and skips a name it
    -- cannot match without a word.
    it("a rowOrder names only spell rows and phase cues of its own encounter, once each", function()
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            local order = enc.rowOrder
            if order ~= nil then
                local ctx = "enc " .. tostring(encId) .. ": rowOrder"
                if type(order) ~= "table" or #order == 0 then
                    failures[#failures + 1] = ctx .. " must be a non-empty list"
                else
                    local seen = {}
                    for i, entry in ipairs(order) do
                        local known = (type(entry) == "number" and type(enc.spells) == "table" and enc.spells[entry] ~= nil)
                            or (type(entry) == "string" and type(enc.phaseCues) == "table" and enc.phaseCues[entry] ~= nil)
                        if not known then
                            failures[#failures + 1] = ctx .. "[" .. i .. "] '" .. tostring(entry) ..
                                "' is not a spell row or cue of this encounter"
                        end
                        if seen[entry] then
                            failures[#failures + 1] = ctx .. "[" .. i .. "] '" .. tostring(entry) .. "' repeats"
                        end
                        seen[entry] = true
                    end
                end
            end
        end
        assert.same({}, failures)
    end)

    -- The stage latch matches a Timer receipt by its curated row and by its
    -- duration rounded to one decimal; a stage cue starts after stage 1.
    it("a stageCue names an explicit Timer row of its own encounter, a one-decimal duration and a later stage", function()
        local bindings = KE._DungeonTimerState.BuildBindings(KE.EncounterData)
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            local cue = enc.stageCue
            if cue ~= nil then
                local ctx = "enc " .. tostring(encId) .. ": stageCue"
                local timers = bindings.timers[encId] or {}
                if type(cue) ~= "table" or not timers[cue.spellID] then
                    failures[#failures + 1] = ctx .. " must name an explicit Timer row"
                elseif not (isPositiveNumber(cue.duration) and (cue.duration * 10) % 1 == 0) then
                    failures[#failures + 1] = ctx .. ".duration must be positive with at most one decimal"
                elseif not (isPositiveNumber(cue.stage) and cue.stage % 1 == 0 and cue.stage >= 2) then
                    failures[#failures + 1] = ctx .. ".stage must be a whole stage number from 2"
                end
            end
        end
        assert.same({}, failures)
    end)

    -- The swap alternates the shield between two boss tokens on one message.
    it("a shieldSwap names a message spell and two boss tokens, one of them its start", function()
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            local swap = enc.shieldSwap
            if swap ~= nil then
                local ctx = "enc " .. tostring(encId) .. ": shieldSwap"
                local units = type(swap) == "table" and swap.units
                local function isBoss(u) return type(u) == "string" and u:match("^boss%d$") ~= nil end
                if not (type(units) == "table" and #units == 2 and isBoss(units[1]) and isBoss(units[2])
                    and units[1] ~= units[2]) then
                    failures[#failures + 1] = ctx .. ".units must be two different bossN tokens"
                elseif not isPositiveNumber(swap.message) then
                    failures[#failures + 1] = ctx .. ".message must be a spell ID"
                elseif swap.start ~= units[1] and swap.start ~= units[2] then
                    failures[#failures + 1] = ctx .. ".start must be one of its units"
                elseif swap.icon ~= nil and not isPositiveNumber(swap.icon) then
                    failures[#failures + 1] = ctx .. ".icon must be a spell ID"
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
            -- missing duration is a dead entry (DungeonTimers.lua).
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
        local failures = forEachSpell(function(failures, ctx, enc, _, spell)
            for _, field in ipairs({ "castDuration", "channelDuration", "forceDuration", "duration" }) do
                -- An explicit encounter's castDuration may be zero; the explicit
                -- contract case enforces its own >= 0 domain.
                local explicitCast = field == "castDuration" and enc.timerPolicy == "explicit"
                if spell[field] ~= nil and not explicitCast and not isPositiveNumber(spell[field]) then
                    failures[#failures + 1] = ctx .. ": " .. field .. " must be a positive number"
                end
            end
            -- showAtSeconds = 0 is meaningful ("force always visible",
            -- EncounterData.lua), so 0 is allowed here.
            if spell.showAtSeconds ~= nil
                and (type(spell.showAtSeconds) ~= "number" or spell.showAtSeconds < 0) then
                failures[#failures + 1] = ctx .. ": showAtSeconds must be a number >= 0"
            end
            if spell.castType == "channel" and not isPositiveNumber(spell.channelDuration) then
                failures[#failures + 1] = ctx .. ": channel castType requires channelDuration"
            end
            -- extendByChannel without channelDuration is a silent no-op in
            -- GetSpellExtension (DungeonTimers.lua) — curator error.
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
                    -- RenderPresentation drops baseDur <= 0 (DungeonTimers.lua):
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
            lintColor(failures, ctx, "shieldColor", spell.shieldColor)
            if type(spell.secondary) == "table" then
                lintColor(failures, ctx, "secondary.color", spell.secondary.color)
            end
        end)
        assert.same({}, failures)
    end)

    it("phantomFollowupOf resolves to a different spell in the same encounter", function()
        local failures = forEachSpell(function(failures, ctx, enc, spellId, spell)
            if spell.phantomFollowupOf == nil then return end
            -- GetSpellPhantomFollowupOf goes through tonumber (DungeonTimers.lua).
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
            -- (EncounterData.lua); there is no per-cast color field, so
            -- it must resolve — the StopBar swap reads castColor, which is
            -- preset-derived only (DungeonTimers.lua).
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
            -- A shield's displayText (row shieldBar or encounter shields) is
            -- exempt from color resolution: the shield fill color is hardcoded
            -- (DungeonTimers.lua).
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
                        -- (DungeonTimers.lua) — a non-positive curated
                        -- lead is a dead rule.
                        if not isPositiveNumber(rule.lead) then
                            failures[#failures + 1] = ctx .. ": lead must be a positive number"
                        end
                        -- endsAtStage is compared with the encounter
                        -- stage, which is a whole number from 1.
                        if rule.endsAtStage ~= nil and not (isPositiveNumber(rule.endsAtStage)
                            and rule.endsAtStage % 1 == 0) then
                            failures[#failures + 1] = ctx .. ": endsAtStage must be a whole stage number from 1"
                        end
                        -- endsOnShield is decided by the encounter's shieldSwap.
                        if rule.endsOnShield ~= nil and not (rule.endsOnShield == true and enc.shieldSwap ~= nil) then
                            failures[#failures + 1] = ctx .. ": endsOnShield must be true on an encounter with a shieldSwap"
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
            -- (DungeonTimers.lua): a non-uppercase key is unreachable by key.
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
            -- Alias lookup upper-cases the INPUT only (DungeonTimers.lua);
            -- a non-uppercase alias key never matches.
            if aliasKey ~= aliasKey:upper() then
                failures[#failures + 1] = "alias '" .. aliasKey .. "': key must be uppercase"
            end
            -- A dangling alias silently falls through to the default color
            -- (guard at DungeonTimers.lua).
            if DT.DISPLAY_PRESETS[target] == nil then
                failures[#failures + 1] = "alias '" .. tostring(aliasKey) .. "': target '" ..
                    tostring(target) .. "' is not a preset"
            end
        end
        assert.same({}, failures)
    end)

    -- Mirrors TimerState.lua's BuildExplicitTimerBinding/HasForbiddenExplicitField so a row
    -- that satisfies this lint is guaranteed a real binding, not silently dropped at runtime.
    local EXPLICIT_FORBIDDEN_FIELDS = {
        "channelDuration", "forceDuration", "postCastBar", "phantomFollowupOf",
        "spawnOnMessage", "shieldBar", "secondary", "castDisplayText",
    }

    local function isFiniteNumber(v)
        return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
    end

    -- Mirrors TimerState.lua's BuildSequelBindings: a Sequel row that passes
    -- here must own the sequel binding installed under its parent.
    local function lintSequel(failures, ctx, encId, enc, spellId, spell, bindings)
        local contract = spell.timerSource
        local parentId = contract.parent
        if not isFiniteNumber(parentId) or parentId == spellId or enc.spells[parentId] == nil then
            failures[#failures + 1] = ctx .. ": timerSource.parent must name another row of this encounter"
        end
        if not (isFiniteNumber(contract.after) and contract.after >= 0) then
            failures[#failures + 1] = ctx .. ": timerSource.after must be a finite number >= 0"
        end
        if not (isFiniteNumber(spell.castDuration) and spell.castDuration >= 0) then
            failures[#failures + 1] = ctx .. ": sequel row requires a finite castDuration >= 0"
        elseif isFiniteNumber(contract.after) and contract.after + spell.castDuration <= 0 then
            failures[#failures + 1] = ctx .. ": sequel after + castDuration must be > 0"
        end
        for _, field in ipairs(EXPLICIT_FORBIDDEN_FIELDS) do
            if spell[field] ~= nil then
                failures[#failures + 1] = ctx .. ": sequel row must not carry " .. field
            end
        end
        if spell.extendByChannel == true then
            failures[#failures + 1] = ctx .. ": sequel row must not set extendByChannel"
        end
        local byParent = bindings.sequels[encId]
        local installed = isFiniteNumber(parentId) and byParent and byParent[parentId]
        if not (installed and installed.key == spellId) then
            failures[#failures + 1] = ctx ..
                ": sequel row passes this lint but the runtime builder installed no sequel binding"
        end
    end

    it("explicit timer contracts are well-formed and agree with the runtime builder", function()
        local bindings = KE._DungeonTimerState.BuildBindings(KE.EncounterData)
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            local ctxEnc = "enc " .. tostring(encId)
            if enc.timerPolicy ~= nil and enc.timerPolicy ~= "explicit" then
                failures[#failures + 1] = ctxEnc .. ": timerPolicy must be nil or 'explicit'"
            end
            for spellId, spell in pairs(type(enc.spells) == "table" and enc.spells or {}) do
                local ctx = string.format("enc %s (%s) spell %s",
                    tostring(encId), tostring(enc.name), tostring(spellId))
                if enc.timerPolicy ~= "explicit" then
                    if spell.timerSource ~= nil then
                        failures[#failures + 1] = ctx ..
                            ": timerSource requires the encounter's timerPolicy to be 'explicit'"
                    end
                elseif type(spell.timerSource) == "table" and spell.timerSource.kind == "Sequel" then
                    lintSequel(failures, ctx, encId, enc, spellId, spell, bindings)
                else
                    local contract = spell.timerSource
                    if type(contract) ~= "table" then
                        failures[#failures + 1] = ctx .. ": explicit encounter row must carry a timerSource table"
                    else
                        if contract.kind ~= "Timer" then
                            failures[#failures + 1] = ctx .. ": timerSource.kind must be 'Timer'"
                        end
                        if contract.isCooldown ~= true then
                            failures[#failures + 1] = ctx .. ": timerSource.isCooldown must be true"
                        end
                        if contract.policy ~= "estimated-impact" then
                            failures[#failures + 1] = ctx .. ": timerSource.policy must be 'estimated-impact'"
                        end
                        if contract.spanMode ~= "remaining-only" then
                            failures[#failures + 1] = ctx .. ": timerSource.spanMode must be 'remaining-only'"
                        end
                        if contract.collisionPolicy ~= "refuse-unresolved-label" then
                            failures[#failures + 1] = ctx .. ": timerSource.collisionPolicy must be 'refuse-unresolved-label'"
                        end
                        if not (isFiniteNumber(contract.stopTolerance) and contract.stopTolerance > 0) then
                            failures[#failures + 1] = ctx .. ": timerSource.stopTolerance must be a finite number > 0"
                        end
                        if contract.anchor ~= nil and contract.anchor ~= "timeline-finished" then
                            failures[#failures + 1] = ctx .. ": timerSource.anchor must be nil or 'timeline-finished'"
                        end
                        if contract.castConfirm ~= nil and contract.castConfirm ~= "boss-cast-start" then
                            failures[#failures + 1] = ctx .. ": timerSource.castConfirm must be nil or 'boss-cast-start'"
                        end
                        local canceledStop = contract.canceledStop
                        if canceledStop ~= nil then
                            if type(canceledStop) ~= "table" or not isFiniteNumber(canceledStop.stage)
                                or canceledStop.stage <= 0 or not isFiniteNumber(canceledStop.within)
                                or canceledStop.within <= 0 or canceledStop.within > 1 then
                                failures[#failures + 1] = ctx .. ": timerSource.canceledStop needs stage > 0 and 0 < within <= 1"
                            end
                            if contract.anchor ~= "timeline-finished" or contract.castConfirm ~= nil
                                or contract.pausedStop ~= nil or contract.queueAfter ~= nil then
                                failures[#failures + 1] = ctx ..
                                    ": timerSource.canceledStop needs the anchor and no castConfirm, pausedStop or queueAfter"
                            end
                        end
                        local retainEarlyFinished = contract.retainEarlyFinished
                        if retainEarlyFinished ~= nil and (retainEarlyFinished ~= true
                            or contract.anchor ~= "timeline-finished" or contract.castConfirm ~= nil
                            or contract.pausedStop ~= nil or contract.queueAfter ~= nil or canceledStop ~= nil) then
                            failures[#failures + 1] = ctx ..
                                ": retainEarlyFinished needs true, the anchor and no other stop/queue policy"
                        end
                        local restart = contract.suppressConcurrentRestart
                        if restart ~= nil and (type(restart) ~= "table"
                            or not isFiniteNumber(restart.from) or not isFiniteNumber(restart.duration)
                            or restart.duration <= 0 or restart.from <= restart.duration
                            or contract.anchor ~= "timeline-finished" or contract.castConfirm ~= nil
                            or contract.pausedStop ~= nil or contract.queueAfter ~= nil
                            or canceledStop ~= nil or retainEarlyFinished ~= nil) then
                            failures[#failures + 1] = ctx ..
                                ": suppressConcurrentRestart needs from > duration > 0, an anchor and no other stop/queue policy"
                        end
                        if canceledStop ~= nil or retainEarlyFinished ~= nil or restart ~= nil then
                            -- These dependents need every published occurrence to reach an anchor.
                            local installed = bindings.timers[encId] and bindings.timers[encId][spellId]
                            local shieldParent = bindings.shields[encId] and bindings.shields[encId][spellId]
                            local cueEnder = bindings.cueEnders[encId] and bindings.cueEnders[encId][spellId]
                            if (installed and installed.ownsExpiry) or shieldParent or cueEnder then
                                failures[#failures + 1] = ctx ..
                                    ": a retained or suppressed row may not own its expiry, parent a shield or end a cue"
                            end
                        end
                    end
                    if not (isFiniteNumber(spell.castDuration) and spell.castDuration >= 0) then
                        failures[#failures + 1] = ctx .. ": explicit row requires a finite castDuration >= 0"
                    end
                    for _, field in ipairs(EXPLICIT_FORBIDDEN_FIELDS) do
                        if spell[field] ~= nil then
                            failures[#failures + 1] = ctx .. ": explicit row must not carry " .. field
                        end
                    end
                    if spell.extendByChannel == true then
                        failures[#failures + 1] = ctx .. ": explicit row must not set extendByChannel"
                    end
                    local timersForEncounter = bindings.timers[encId]
                    if not (timersForEncounter and timersForEncounter[spellId]) then
                        failures[#failures + 1] = ctx ..
                            ": row passes this lint but the runtime builder installed no binding"
                    end
                end
            end
        end
        assert.same({}, failures)
    end)

    it("phase cues are well-formed and agree with the runtime builder", function()
        local State = KE._DungeonTimerState
        local bindings = State.BuildBindings(KE.EncounterData)
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            if enc.phaseCues ~= nil then
                if enc.timerPolicy ~= "explicit" then
                    failures[#failures + 1] = "enc " .. tostring(encId) ..
                        ": phaseCues requires the encounter's timerPolicy to be 'explicit'"
                end
                for cueName, cue in pairs(type(enc.phaseCues) == "table" and enc.phaseCues or {}) do
                    local ctx = string.format("enc %s (%s) cue %s",
                        tostring(encId), tostring(enc.name), tostring(cueName))
                    if type(cue.name) ~= "string" or cue.name == "" then
                        failures[#failures + 1] = ctx .. ": name must be a non-empty string"
                    end
                    if type(cue.iconOverride) ~= "number" and type(cue.iconOverride) ~= "string" then
                        failures[#failures + 1] = ctx .. ": iconOverride must be a spell ID, texture ID or path"
                    end
                    if cue.role ~= nil and not ROLES[cue.role] then
                        failures[#failures + 1] = ctx .. ": unknown role '" .. tostring(cue.role) .. "'"
                    end
                    if cue.display ~= nil and not DISPLAYS[cue.display] then
                        failures[#failures + 1] = ctx .. ": unknown display '" .. tostring(cue.display) .. "'"
                    end
                    lintColor(failures, ctx, "color", cue.color)
                    lintColor(failures, ctx, "endedColor", cue.endedColor)
                    local hasColor = cue.color ~= nil
                    lintLabel(failures, ctx, "displayText", cue.displayText, hasColor)
                    lintLabel(failures, ctx, "prepareText", cue.prepareText, hasColor)
                    lintLabel(failures, ctx, "endedText", cue.endedText, hasColor or cue.endedColor ~= nil)

                    local source = type(cue.source) == "table" and cue.source or {}
                    local installed
                    if source.kind == "Message" and source.key ~= nil then
                        installed = bindings.messages[encId] and bindings.messages[encId][source.key]
                    elseif source.kind == "Timer" and source.key ~= nil then
                        installed = bindings.phaseTimers[encId] and bindings.phaseTimers[encId][source.key]
                    elseif source.kind == "Sequel" and source.parent ~= nil then
                        installed = bindings.sequels[encId] and bindings.sequels[encId][source.parent]
                    end
                    if not (installed and installed.cueKey == State.CueKey(encId, cueName)) then
                        failures[#failures + 1] = ctx .. ": the runtime builder installed no binding for this cue"
                    end
                end
            end
        end
        assert.same({}, failures)
    end)

    it("curated queue relations and forecast gates install their runtime bindings", function()
        local State = KE._DungeonTimerState
        local bindings = State.BuildBindings(KE.EncounterData)
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            for spellId, spell in pairs(type(enc.spells) == "table" and enc.spells or {}) do
                local contract = type(spell.timerSource) == "table" and spell.timerSource or {}
                local queueAfter = contract.queueAfter
                if queueAfter ~= nil then
                    local parentId = type(queueAfter) == "table" and queueAfter.parent or nil
                    local byParent = bindings.queues[encId]
                    local installed = parentId ~= nil and byParent and byParent[parentId]
                    if not (installed and installed.target == spellId) then
                        failures[#failures + 1] = string.format(
                            "enc %s spell %s: queueAfter installed no queue binding", tostring(encId), tostring(spellId))
                    end
                end
            end
            for cueName, cue in pairs(type(enc.phaseCues) == "table" and enc.phaseCues or {}) do
                if cue.hidesForecasts ~= nil then
                    local gates = bindings.forecastGates[encId]
                    if not (gates and gates[State.CueKey(encId, cueName)]) then
                        failures[#failures + 1] = string.format(
                            "enc %s cue %s: hidesForecasts installed no forecast gate", tostring(encId), tostring(cueName))
                    end
                end
            end
        end
        assert.same({}, failures)
    end)

    it("boss shield entries sit in explicit encounters and install their runtime shield binding", function()
        local bindings = KE._DungeonTimerState.BuildBindings(KE.EncounterData)
        local failures = {}
        for encId, enc in pairs(KE.EncounterData) do
            if enc.shields ~= nil then
                if enc.timerPolicy ~= "explicit" then
                    failures[#failures + 1] = "enc " .. tostring(encId) ..
                        ": shields requires the encounter's timerPolicy to be 'explicit'"
                end
                for i, entry in ipairs(type(enc.shields) == "table" and enc.shields or {}) do
                    local ctx = string.format("enc %s (%s) shield %d", tostring(encId), tostring(enc.name), i)
                    local parentId = type(entry) == "table" and entry.parent or nil
                    local byParent = bindings.shields[encId]
                    local installed = parentId ~= nil and byParent and byParent[parentId]
                    if not (installed and installed.explicit) then
                        failures[#failures + 1] = ctx .. ": the runtime builder installed no shield binding"
                    end
                end
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
        assert.same({ 0.3, 0.5, 0.9 }, bar.barColor)  -- DEFAULT_BAR_COLOR (DungeonTimers.lua)
    end)

    it("nil displayText falls back to the BigWigs text with the ' (N)' counter stripped", function()
        local bar = DT:CreateBar("Fireball (2)", 5, 0, "bar", nil)
        assert.equals("Fireball", bar.baseText)
        -- Strip is end-anchored (StripBigWigsCounter, DungeonTimers.lua).
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

-- A leftover media file alone does not prove its sound name is registered.
describe("DungeonTimers EncounterData - aura sound rules", function()
    local DT, KE
    local registered = {}

    setup(function()
        L.loadGlobals(nil, { onMediaRegister = function(kind, name)
            if kind == "sound" then registered[name] = true end
        end })
        DT, KE = L.loadDungeonTimers({ withEncounterData = true })
    end)

    it("every aura sound rule is well-formed, unique per dungeon and names a registered sound whose file ships", function()
        local failures, seen = {}, {}
        for encId, enc in pairs(KE.EncounterData) do
            for i, rule in ipairs(type(enc.auraSounds) == "table" and enc.auraSounds or {}) do
                local ctx = string.format("enc %s (%s) aura rule %d", tostring(encId), tostring(enc.name), i)
                if not DT.IsWellFormedAuraRule(rule) then
                    failures[#failures + 1] = ctx .. ": malformed (fields, spellID, trigger, unit, name, sound or disabled)"
                else
                    local dupKey = tostring(enc.dungeon) .. ":" .. rule.spellID .. ":" .. rule.trigger
                    if seen[dupKey] then
                        failures[#failures + 1] = ctx .. ": duplicate spell and trigger within the dungeon"
                    end
                    seen[dupKey] = true
                    if not registered[rule.sound] then
                        failures[#failures + 1] = ctx .. ": sound '" .. rule.sound .. "' is not a registered sound name"
                    end
                    local file = io.open("Media/Sounds/" .. rule.sound .. ".ogg", "rb")
                    if file then
                        file:close()
                    else
                        failures[#failures + 1] = ctx .. ": sound '" .. rule.sound .. "' has no file under Media/Sounds"
                    end
                end
            end
        end
        assert.same({}, failures)
        assert.is_true(next(registered) ~= nil, "the loader hook collected no registered sound name")
    end)

    it("every curated spell, cue and phase sound names a registered sound whose file ships", function()
        local failures = {}
        local function check(ctx, field, name)
            if name == nil then return end
            if type(name) ~= "string" or not registered[name] then
                failures[#failures + 1] = ctx .. ": " .. field .. " '" .. tostring(name) .. "' is not a registered sound name"
                return
            end
            local file = io.open("Media/Sounds/" .. name .. ".ogg", "rb")
            if file then
                file:close()
            else
                failures[#failures + 1] = ctx .. ": " .. field .. " '" .. name .. "' has no file under Media/Sounds"
            end
        end
        local function checkRow(ctx, row)
            if type(row) ~= "table" then return end
            check(ctx, "sound", row.sound)
            check(ctx, "soundOnHide", row.soundOnHide)
            if row.ordinalSounds ~= nil then
                if type(row.ordinalSounds) ~= "table" then
                    failures[#failures + 1] = ctx .. ": ordinalSounds must be a list"
                else
                    for i, name in ipairs(row.ordinalSounds) do
                        check(ctx, "ordinalSounds[" .. i .. "]", name)
                    end
                end
            end
        end
        for encId, enc in pairs(KE.EncounterData) do
            local prefix = string.format("enc %s (%s)", tostring(encId), tostring(enc.name))
            for spellId, spell in pairs(type(enc.spells) == "table" and enc.spells or {}) do
                checkRow(prefix .. " spell " .. tostring(spellId), spell)
            end
            for cueName, cue in pairs(type(enc.phaseCues) == "table" and enc.phaseCues or {}) do
                checkRow(prefix .. " cue " .. tostring(cueName), cue)
            end
            for i, rule in ipairs(type(enc.phases) == "table" and enc.phases or {}) do
                checkRow(prefix .. " phase " .. i, rule)
            end
        end
        assert.same({}, failures)
    end)
end)

local L = require("dev.spec._ke_loader")

local SEVEN = { 6940, 47788, 255312, 102342, 116849, 357170, 53480 }

-- A recording API. failOn makes the Nth Add return nil so the unrestricted
-- failure path can be exercised without a stateful fake of Blizzard's side.
local function apiRecording(failOn)
    local rec = { added = {}, removed = {}, nextID = 0 }
    rec.api = {
        Add = function(_, payload)
            rec.added[#rec.added + 1] = payload
            if failOn and #rec.added == failOn then return nil end
            rec.nextID = rec.nextID + 1
            return rec.nextID
        end,
        Remove = function(id) rec.removed[#rec.removed + 1] = id end,
    }
    return rec
end

local function registryWith(rec, hidden, media)
    local S = L.loadAuraSound()
    local state = { hidden = hidden }
    local reg = S.New({
        api          = rec.api,
        resolveMedia = media or function(name) return name and "path/" .. name or nil end,
        isHidden     = function() return state.hidden end,
        onDiagnostic = function(msg) rec.diagnostics = (rec.diagnostics or 0) + 1; rec.lastMsg = msg end,
    })
    return reg, state
end

local DECL = { spellIDs = SEVEN, unit = "player", settingKeys = { enabled = "SoundEnabled", name = "SoundName" } }

describe("desired sound registry condition", function()
    it("registers exactly seven when every input is satisfied", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Bell" }, true)
        assert.equals(7, #rec.added)
        assert.equals(7, reg:Count())
    end)

    it("registers nothing when the module is disabled", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Bell" }, false)
        assert.equals(0, #rec.added)
    end)

    it("registers nothing when SoundEnabled is false", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = false, SoundName = "Bell" }, true)
        assert.equals(0, #rec.added)
    end)

    it("registers nothing for the None sentinel", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "None" }, true)
        assert.equals(0, #rec.added)
    end)

    it("registers nothing when the media library cannot resolve the key", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false, function() return nil end)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Missing" }, true)
        assert.equals(0, #rec.added)
    end)

    it("passes the resolved PATH, not the stored key", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Bell" }, true)
        assert.equals("path/Bell", rec.added[1].soundFileName)
        assert.equals("player", rec.added[1].unitToken)
        assert.equals("Master", rec.added[1].outputChannel)
    end)

    -- The no-op branch. Every settings change routes through Sync, so without
    -- this the registry is torn down and rebuilt when the user moves a font
    -- slider — and inside a keystone the rebuild half is refused, which loses
    -- the sound for the rest of the key.
    it("does nothing when the desired sound has not changed", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        local settings = { SoundEnabled = true, SoundName = "Bell" }

        reg:Sync(DECL, settings, true)
        local addedAfterFirst = #rec.added

        reg:Sync(DECL, settings, true)
        assert.equals(addedAfterFirst, #rec.added)
        assert.equals(0, #rec.removed)
        assert.is_false(reg:IsPending())
    end)

    it("still rebuilds when the desired sound actually changes", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Bell" }, true)
        local first = #rec.added

        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Horn" }, true)
        assert.is_true(#rec.removed > 0)
        assert.is_true(#rec.added > first)
    end)

    -- A restricted sync leaves currentPath unset, so the next unrestricted
    -- sync must NOT mistake the deferred attempt for a live registration.
    it("does not no-op after a deferred sync", function()
        local rec = apiRecording()
        local reg = registryWith(rec, true)
        local settings = { SoundEnabled = true, SoundName = "Bell" }

        reg:Sync(DECL, settings, true)
        assert.equals(0, #rec.added)
        assert.is_true(reg:IsPending())

        reg.isHidden = function() return false end
        reg:Sync(DECL, settings, true)
        assert.is_true(#rec.added > 0)
        assert.is_false(reg:IsPending())
    end)

    it("registers nothing at all for a display that declares no sounds", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(nil, { SoundEnabled = true, SoundName = "Bell" }, true)
        assert.equals(0, #rec.added)
        assert.is_false(reg:IsPending())
    end)
end)

describe("restricted intermediates", function()
    -- Retire always works; Add is the restricted half. So a stale sound is
    -- removed immediately and the desired set waits.
    it("retires immediately and pends when restricted", function()
        local rec = apiRecording()
        local reg, state = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "A" }, true)
        assert.equals(7, #rec.added)

        state.hidden = true
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "B" }, true)

        assert.equals(7, #rec.removed)
        assert.equals(7, #rec.added)   -- nothing new added
        assert.equals(0, reg:Count())  -- empty, never partial
        assert.is_true(reg:IsPending())
    end)

    it("rebuilds from the LATEST settings on release, not the pended ones", function()
        local rec = apiRecording()
        local reg, state = registryWith(rec, false)
        state.hidden = true
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "B" }, true)

        state.hidden = false
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "C" }, true)
        assert.equals("path/C", rec.added[#rec.added].soundFileName)
        assert.is_false(reg:IsPending())
    end)

    -- Switching sound OFF while restricted reaches the desired state
    -- immediately, so there is nothing to wait for.
    it("sets no pending flag when the desired state is silence", function()
        local rec = apiRecording()
        local reg, state = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "A" }, true)

        state.hidden = true
        reg:Sync(DECL, { SoundEnabled = false, SoundName = "A" }, true)

        assert.equals(7, #rec.removed)
        assert.equals(0, reg:Count())
        assert.is_false(reg:IsPending())
    end)
end)

describe("unrestricted registration failure", function()
    -- A nilable return with nothing restricted is a different case: the
    -- pending flag would be waiting on a release that is never coming.
    it("rolls back to empty rather than leaving a partial set", function()
        local rec = apiRecording(3)
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "A" }, true)

        assert.equals(0, reg:Count())
        assert.equals(2, #rec.removed)  -- the two that succeeded before the nil
    end)

    it("CLEARS pending rather than setting it", function()
        local rec = apiRecording(3)
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "A" }, true)
        assert.is_false(reg:IsPending())
    end)

    it("emits exactly one diagnostic, not one per call", function()
        local rec = apiRecording(3)
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "A" }, true)
        assert.equals(1, rec.diagnostics)
    end)

    it("recovers on the next ordinary sync", function()
        local rec = apiRecording(3)
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "A" }, true)

        rec.api.Add = function(_, payload)
            rec.added[#rec.added + 1] = payload
            rec.nextID = rec.nextID + 1
            return rec.nextID
        end
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "A" }, true)
        assert.equals(7, reg:Count())
    end)
end)

describe("retire all", function()
    it("removes every registration and empties the registry", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "A" }, true)
        reg:RetireAll()
        assert.equals(7, #rec.removed)
        assert.equals(0, reg:Count())
    end)

    it("clears any pending debt too", function()
        local rec = apiRecording()
        local reg, state = registryWith(rec, false)
        state.hidden = true
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "A" }, true)
        assert.is_true(reg:IsPending())
        reg:RetireAll()
        assert.is_false(reg:IsPending())
    end)
end)

-- The no-op guard ANDs three conditions, and on both failure paths the id
-- list is emptied anyway. That redundancy hides whether currentPath is
-- actually doing its job: a regression that stopped clearing it, or that set
-- it before the add loop finished, would still pass every test above. These
-- isolate it.
describe("sound registry currentPath discipline", function()
    -- Both of these register successfully FIRST. Starting from a fresh
    -- registry would assert that a never-set field is nil, which is true of
    -- any implementation and proves nothing.
    it("CLEARS a previously recorded currentPath on a deferred sync", function()
        local rec = apiRecording()
        local reg, state = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Bell" }, true)
        assert.equals("path/Bell", reg.currentPath)

        state.hidden = true
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Horn" }, true)

        assert.is_nil(reg.currentPath)
        assert.is_true(reg:IsPending())
    end)

    it("CLEARS a previously recorded currentPath on a rolled back sync", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Bell" }, true)
        assert.equals("path/Bell", reg.currentPath)

        -- Make the next attempt's fourth Add return nil.
        rec.api.Add = function(_, payload)
            rec.added[#rec.added + 1] = payload
            if #rec.added == 11 then return nil end
            rec.nextID = rec.nextID + 1
            return rec.nextID
        end
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Horn" }, true)

        assert.is_nil(reg.currentPath)
        assert.is_false(reg:IsPending())
        assert.equals(0, #reg.ids)
    end)

    it("records currentPath only once the whole set registered", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Bell" }, true)
        assert.equals("path/Bell", reg.currentPath)
    end)

    -- The masking case, driven directly: ids present and nothing pending, so
    -- the other two guard conditions both say "skip". Only currentPath can
    -- force the rebuild, so this fails if it is ignored.
    it("rebuilds when currentPath alone is stale", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Bell" }, true)
        assert.equals(7, #rec.added)

        reg.currentPath = "path/SomethingElse"
        reg:Sync(DECL, { SoundEnabled = true, SoundName = "Bell" }, true)

        assert.equals(14, #rec.added)
        assert.equals(7, #rec.removed)
    end)
end)

-- The declaration may BUILD its list from the settings rather than name one.
-- The registry's no-op guard compares the sound path; without a second
-- comparison on the id list, editing the allowlist would leave the previous
-- registrations standing and the newly enabled spell silent.
describe("declarations that build their spell list", function()
    local function builtDecl()
        return {
            buildSpellIDs = function(settings) return settings.ids or {} end,
            unit          = "player",
            settingKeys   = { enabled = "SoundEnabled", name = "SoundName" },
        }
    end

    it("registers the built list rather than a declared one", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(builtDecl(), { SoundEnabled = true, SoundName = "Bell", ids = { 111, 222 } }, true)
        assert.equals(2, #rec.added)
        assert.equals(111, rec.added[1].spellID)
        assert.equals(222, rec.added[2].spellID)
    end)

    it("still no-ops when neither the sound nor the list changed", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        local settings = { SoundEnabled = true, SoundName = "Bell", ids = { 111, 222 } }
        reg:Sync(builtDecl(), settings, true)
        reg:Sync(builtDecl(), settings, true)
        assert.equals(2, #rec.added)
        assert.equals(0, #rec.removed)
    end)

    it("rebuilds when the list changes under an unchanged sound", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(builtDecl(), { SoundEnabled = true, SoundName = "Bell", ids = { 111 } }, true)
        reg:Sync(builtDecl(), { SoundEnabled = true, SoundName = "Bell", ids = { 111, 222 } }, true)
        assert.equals(3, #rec.added)
        assert.equals(1, #rec.removed)
        assert.equals(222, rec.added[3].spellID)
    end)

    it("registers nothing when the built list is empty", function()
        local rec = apiRecording()
        local reg = registryWith(rec, false)
        reg:Sync(builtDecl(), { SoundEnabled = true, SoundName = "Bell", ids = {} }, true)
        assert.equals(0, #rec.added)
    end)
end)

-- GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua — the Frame Skins grid's
-- three-state suppression handling (Task 0C). The file only READS
-- KE.GUIFrame, so it loads against a hand-built stub (GUI-Core.lua creates
-- the real GUIFrame table and would clobber a stub). Widget factories on the
-- stub record what the REAL production callbacks ask them to render, so
-- assertions run against the actual registered content builder, never an
-- extracted policy helper.
--
-- Every test constructs the "partial" state itself by stubbing
-- KE.Skins.GetSuppressionState (rule 1) -- FRAME_SKINS carries no key that is
-- really partial today. Housing and Delves, the only two currently-partial
-- EllesmereUI windows, are real Blizzard windows that land as FRAME_SKINS
-- rows in a later task in this plan, not ADDON_SKINS rows -- so stubbing the
-- accessor is the only way to exercise the three-state branch at all right
-- now.
local helpers = require("dev.spec._helpers")

describe("GUI-BlizzardFrames: Frame Skins grid suppression state", function()
    local KE, GUIFrame, checkboxes, headerToggle, calls, states

    -- calls records every key GetSuppressionState was asked about, in call
    -- order -- this is what proves each production site (not just an
    -- isolated helper) reaches the accessor (rule 6).
    -- states[key] = { state, euiKey, partialLabel, partialTooltip }, the
    -- exact shape S.GetSuppressionState itself returns.
    local function stubGetSuppressionState(key)
        calls[#calls + 1] = key
        local row = states[key]
        if not row then return "none" end
        return row[1], row[2], row[3], row[4]
    end

    -- Mirrors the RAW suppression shape (EUIWindows.lua:176-209: an
    -- unfiltered/"full" row is a bare euiKey STRING, a filtered/"partial" row
    -- is a TABLE) into KE.Skins.suppressed alongside the stubbed accessor
    -- answer. Without this, KE.Skins.suppressed stays empty, so a site that
    -- regressed to reading it directly instead of calling the accessor would
    -- see nil (falsy) for every key -- indistinguishable from "not
    -- suppressed", which is exactly what several of the assertions below
    -- already expect. That would make a raw-read regression invisible. Real
    -- shapes make a raw read reproduce the OLD two-state behaviour instead
    -- (any truthy value, string or table, greys the row out) -- the opposite
    -- of what today's "partial rows stay on" assertions require, so a
    -- regression actually fails them.
    local function seedFull(key, euiKey)
        euiKey = euiKey or "someEuiKey"
        states[key] = { "full", euiKey }
        KE.Skins.suppressed[key] = euiKey
    end

    local function seedPartial(key, euiKey, partialLabel, partialTooltip)
        euiKey = euiKey or "someEuiKey"
        states[key] = { "partial", euiKey, partialLabel, partialTooltip }
        KE.Skins.suppressed[key] = {
            euiKey = euiKey,
            addons = {},
            partialLabel = partialLabel,
            partialTooltip = partialTooltip,
        }
    end

    local function freshDB(skins)
        return { Skins = skins }
    end

    local function containsKey(list, key)
        for _, k in ipairs(list) do
            if k == key then return true end
        end
        return false
    end

    before_each(function()
        states = {}
        calls = {}
        checkboxes = {}
        headerToggle = nil

        GUIFrame = {
            registeredContent = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            RegisterTabbedContent = function() end,
            CreateCard = function()
                local card = { content = {} }
                function card:AddRow() end
                function card:AddLabel() end
                function card:AddHeaderToggle(anyOn, callback)
                    -- Snapshot `calls` HERE, not later. AddHeaderToggle is
                    -- invoked between the header anyOn loop and
                    -- BuildCheckGrid in the real registered callback, so a
                    -- copy taken at this exact moment is precisely the
                    -- header loop's own call list -- BuildCheckGrid asking
                    -- about the same keys afterward, in the same order,
                    -- cannot leak into it and make the assertion vacuous.
                    local snapshot = {}
                    for idx, key in ipairs(calls) do snapshot[idx] = key end
                    headerToggle = { anyOn = anyOn, callback = callback, callsAtRegistration = snapshot }
                end
                function card:GetNextOffset() return 0 end
                return card
            end,
            CreateRow = function()
                local row = { widgets = {} }
                function row:AddWidget(widget) self.widgets[#self.widgets + 1] = widget end
                return row
            end,
            CreateCheckbox = function(_, _, label, config)
                local checkbox = {
                    label = label,
                    tooltip = config.tooltip,
                    value = config.value,
                    callback = config.callback,
                    enabled = true,
                }
                function checkbox:SetEnabled(v) self.enabled = v end
                checkboxes[#checkboxes + 1] = checkbox
                return checkbox
            end,
            RefreshContent = function() end,
        }

        KE = {
            GUIFrame = GUIFrame,
            Skins = { GetSuppressionState = stubGetSuppressionState, suppressed = {} },
            db = { profile = { Skinning = { BlizzardFrames = freshDB({}) } } },
            SkinningReloadPrompt = function() end,
        }
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua", KE)
    end)

    -- Invokes the REAL registered content builder for the Frames tab.
    -- Achievement is FRAME_SKINS entry #1 (alphabetically first as of Task
    -- 15's wiring), so checkboxes[1] is always its row -- the grid renders
    -- every entry every time, regardless of which key's state a test is
    -- exercising.
    local function buildFrames()
        GUIFrame.registeredContent["SkinBlizzardFramesFrames"](nil, 0)
    end

    describe("row rendering across all three states (same key: Achievement)", function()
        it("none: renders unchanged, no tooltip, not disabled", function()
            buildFrames()
            assert.equal("Achievements", checkboxes[1].label)
            assert.is_nil(checkboxes[1].tooltip)
            assert.is_true(checkboxes[1].enabled)
        end)

        it("full: greys the label, sets the suppression tooltip, disables", function()
            seedFull("Achievement")
            buildFrames()
            assert.equal("Achievements |cff888888(EllesmereUI)|r", checkboxes[1].label)
            assert.equal(
                "EllesmereUI already skins this window, so KitnEssentials leaves it alone. Turn EllesmereUI's window skin off to use this one.",
                checkboxes[1].tooltip)
            assert.is_false(checkboxes[1].enabled)
        end)

        it("partial: renders the map row's own label/tooltip verbatim, stays enabled", function()
            seedPartial("Achievement", nil, "Achievements (EllesmereUI: dashboard only)", "Custom partial tooltip text")
            buildFrames()
            -- Positive control: the label is NOT entry.text -- proves the
            -- row actually switched off the "none" rendering above.
            assert.equal("Achievements (EllesmereUI: dashboard only)", checkboxes[1].label)
            assert.equal("Custom partial tooltip text", checkboxes[1].tooltip)
            -- The negative assertion the whole feature exists for: a
            -- partial row must NOT be disabled.
            assert.is_true(checkboxes[1].enabled)
        end)

        it("partial with no map strings: falls back to entry.text plus a generic suffix, never nil", function()
            seedPartial("Achievement")
            buildFrames()
            assert.equal("Achievements |cff888888(EllesmereUI)|r", checkboxes[1].label)
            -- The fallback wording is PARTIAL-specific, not the "full"
            -- suppression tooltip -- that one claims KitnEssentials leaves
            -- the window alone entirely, which is false next to a live,
            -- clickable partial row.
            assert.equal(
                "EllesmereUI covers part of this window group. This toggle still controls the rest.",
                checkboxes[1].tooltip)
            assert.is_true(checkboxes[1].enabled)
        end)
    end)

    describe("header anyOn, in isolation", function()
        -- A metatable default of `false` models "every row off" without
        -- hardcoding the full FRAME_SKINS key list (76 entries) -- only the
        -- designated key is given a real, on-reading value.
        local function allOffExcept(key, value)
            return setmetatable({ [key] = value }, { __index = function() return false end })
        end

        it("reads on when every other row is off and only the partial row's setting is on", function()
            seedPartial("Socket")
            KE.db.profile.Skinning.BlizzardFrames = freshDB(allOffExcept("Socket", true))
            buildFrames()
            assert.is_true(headerToggle.anyOn)
        end)

        it("positive control: reads off when the partial row is ALSO off", function()
            seedPartial("Socket")
            KE.db.profile.Skinning.BlizzardFrames = freshDB(allOffExcept("Socket", false))
            buildFrames()
            assert.is_false(headerToggle.anyOn)
        end)

        it("calls the accessor per row, in FRAME_SKINS order, until it finds one on", function()
            -- Achievement (#1) off, AddonManager (#2) on and unsuppressed:
            -- anyOn must consult the accessor for Achievement, then
            -- AddonManager, then stop. Asserted against the snapshot
            -- AddHeaderToggle's stub takes at registration time (BEFORE
            -- BuildCheckGrid re-walks the same keys), so this is provably the
            -- header loop's OWN call list -- deleting the accessor call from
            -- that loop leaves the snapshot empty and fails this assertion,
            -- regardless of what BuildCheckGrid does afterward.
            KE.db.profile.Skinning.BlizzardFrames = freshDB({ Achievement = false })
            buildFrames()
            assert.same({ "Achievement", "AddonManager" }, headerToggle.callsAtRegistration)
        end)
    end)

    describe("BuildCheckGrid calls the accessor for every row", function()
        it("reaches the last FRAME_SKINS entry even though anyOn already broke on the first", function()
            -- Default db.Skins (empty): Achievement reads on immediately, so
            -- anyOn's loop calls the accessor exactly once (Achievement) and
            -- breaks. If "WorldMap" (FRAME_SKINS' last entry) still shows up
            -- in `calls`, that call can only have come from BuildCheckGrid,
            -- which renders every row regardless of anyOn's outcome.
            buildFrames()
            assert.is_true(containsKey(calls, "WorldMap"),
                "BuildCheckGrid did not ask about WorldMap (the last FRAME_SKINS row)")
        end)
    end)

    describe("bulk toggle", function()
        it("bulk-off writes the partial row and leaves the fully suppressed row untouched", function()
            seedPartial("Socket")
            seedFull("Barber")
            -- Seeded with a placeholder (true), never the canonical on value
            -- (nil/absent), so a write is observable: an absent key already
            -- reads as on, and would look identical to "never touched".
            KE.db.profile.Skinning.BlizzardFrames = freshDB({ Socket = true, Barber = true })
            buildFrames()
            calls = {}
            headerToggle.callback(false)
            local skins = KE.db.profile.Skinning.BlizzardFrames.Skins
            -- The write: checked=false stores `false`, per SetEntry.
            assert.is_false(skins.Socket)
            -- The negative assertion, paired with the positive one above on
            -- the same bulk call: the fully suppressed row keeps its
            -- placeholder, proving it was skipped, not merely written the
            -- same value back.
            assert.is_true(skins.Barber)
            assert.is_true(containsKey(calls, "Socket"), "bulk-off never asked the accessor about Socket")
            assert.is_true(containsKey(calls, "Barber"), "bulk-off never asked the accessor about Barber")
        end)

        it("bulk-on returns the partial row and leaves the fully suppressed row untouched", function()
            seedPartial("Socket")
            seedFull("Barber")
            -- Seeded with the canonical off value (false) so bulk-on's write
            -- (nil) is observable against it.
            KE.db.profile.Skinning.BlizzardFrames = freshDB({ Socket = false, Barber = false })
            buildFrames()
            calls = {}
            headerToggle.callback(true)
            local skins = KE.db.profile.Skinning.BlizzardFrames.Skins
            -- The write: checked=true stores `nil`, per SetEntry.
            assert.is_nil(skins.Socket)
            assert.is_false(skins.Barber)
            assert.is_true(containsKey(calls, "Socket"), "bulk-on never asked the accessor about Socket")
            assert.is_true(containsKey(calls, "Barber"), "bulk-on never asked the accessor about Barber")
        end)
    end)
end)

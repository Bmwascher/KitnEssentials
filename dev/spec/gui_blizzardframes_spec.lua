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
-- really partial today (Housing/Delves are ADDON_SKINS-shaped rows that
-- don't exist as FRAME_SKINS entries yet), so the only way to exercise the
-- three-state branch at all is to tell the stub what to answer.
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

    local function freshDB(skins)
        return { Skins = skins }
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
                    headerToggle = { anyOn = anyOn, callback = callback }
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
            Skins = { GetSuppressionState = stubGetSuppressionState },
            db = { profile = { Skinning = { BlizzardFrames = freshDB({}) } } },
            SkinningReloadPrompt = function() end,
        }
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua", KE)
    end)

    -- Invokes the REAL registered content builder for the Frames tab.
    -- Barber is FRAME_SKINS entry #1, so checkboxes[1] is always its row --
    -- the grid renders every entry every time, regardless of which key's
    -- state a test is exercising.
    local function buildFrames()
        GUIFrame.registeredContent["SkinBlizzardFramesFrames"](nil, 0)
    end

    describe("row rendering across all three states (same key: Barber)", function()
        it("none: renders unchanged, no tooltip, not disabled", function()
            buildFrames()
            assert.equal("Barbershop", checkboxes[1].label)
            assert.is_nil(checkboxes[1].tooltip)
            assert.is_true(checkboxes[1].enabled)
        end)

        it("full: greys the label, sets the suppression tooltip, disables", function()
            states.Barber = { "full", "someEuiKey" }
            buildFrames()
            assert.equal("Barbershop |cff888888(EllesmereUI)|r", checkboxes[1].label)
            assert.equal(
                "EllesmereUI already skins this window, so KitnEssentials leaves it alone. Turn EllesmereUI's window skin off to use this one.",
                checkboxes[1].tooltip)
            assert.is_false(checkboxes[1].enabled)
        end)

        it("partial: renders the map row's own label/tooltip verbatim, stays enabled", function()
            states.Barber = { "partial", "someEuiKey", "Barbershop (EllesmereUI: dashboard only)", "Custom partial tooltip text" }
            buildFrames()
            -- Positive control: the label is NOT entry.text -- proves the
            -- row actually switched off the "none" rendering above.
            assert.equal("Barbershop (EllesmereUI: dashboard only)", checkboxes[1].label)
            assert.equal("Custom partial tooltip text", checkboxes[1].tooltip)
            -- The negative assertion the whole feature exists for: a
            -- partial row must NOT be disabled.
            assert.is_true(checkboxes[1].enabled)
        end)

        it("partial with no map strings: falls back to entry.text plus the generic suffix, never nil", function()
            states.Barber = { "partial", "someEuiKey" }
            buildFrames()
            assert.equal("Barbershop |cff888888(EllesmereUI)|r", checkboxes[1].label)
            assert.equal(
                "EllesmereUI already skins this window, so KitnEssentials leaves it alone. Turn EllesmereUI's window skin off to use this one.",
                checkboxes[1].tooltip)
            assert.is_true(checkboxes[1].enabled)
        end)
    end)

    describe("header anyOn, in isolation", function()
        -- A metatable default of `false` models "every row off" without
        -- hardcoding the full FRAME_SKINS key list (41 entries and rising) --
        -- only the designated key is given a real, on-reading value.
        local function allOffExcept(key, value)
            return setmetatable({ [key] = value }, { __index = function() return false end })
        end

        it("reads on when every other row is off and only the partial row's setting is on", function()
            states.Socket = { "partial", "someEuiKey" }
            KE.db.profile.Skinning.BlizzardFrames = freshDB(allOffExcept("Socket", true))
            buildFrames()
            assert.is_true(headerToggle.anyOn)
        end)

        it("positive control: reads off when the partial row is ALSO off", function()
            states.Socket = { "partial", "someEuiKey" }
            KE.db.profile.Skinning.BlizzardFrames = freshDB(allOffExcept("Socket", false))
            buildFrames()
            assert.is_false(headerToggle.anyOn)
        end)

        it("calls the accessor per row, in FRAME_SKINS order, until it finds one on", function()
            -- Barber (#1) off, Binding (#2) on and unsuppressed: anyOn must
            -- consult the accessor for Barber, then Binding, then stop --
            -- proof this loop (not just BuildCheckGrid, which runs after it)
            -- reaches S.GetSuppressionState.
            KE.db.profile.Skinning.BlizzardFrames = freshDB({ Barber = false })
            buildFrames()
            assert.equal("Barber", calls[1])
            assert.equal("Binding", calls[2])
        end)
    end)

    describe("BuildCheckGrid calls the accessor for every row", function()
        it("reaches the last FRAME_SKINS entry even though anyOn already broke on the first", function()
            -- Default db.Skins (empty): Barber reads on immediately, so
            -- anyOn's loop calls the accessor exactly once (Barber) and
            -- breaks. If "Trade" (FRAME_SKINS' last entry) still shows up in
            -- `calls`, that call can only have come from BuildCheckGrid,
            -- which renders every row regardless of anyOn's outcome.
            buildFrames()
            local sawTrade = false
            for _, key in ipairs(calls) do
                if key == "Trade" then sawTrade = true end
            end
            assert.is_true(sawTrade, "BuildCheckGrid did not ask about Trade (the last FRAME_SKINS row)")
        end)
    end)

    describe("bulk toggle", function()
        it("bulk-off writes the partial row and leaves the fully suppressed row untouched", function()
            states.Socket = { "partial", "someEuiKey" }
            states.Barber = { "full", "someEuiKey" }
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
            assert.is_true(#calls > 0, "bulk-off never asked the accessor about any row")
        end)

        it("bulk-on returns the partial row and leaves the fully suppressed row untouched", function()
            states.Socket = { "partial", "someEuiKey" }
            states.Barber = { "full", "someEuiKey" }
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
            assert.is_true(#calls > 0, "bulk-on never asked the accessor about any row")
        end)
    end)
end)

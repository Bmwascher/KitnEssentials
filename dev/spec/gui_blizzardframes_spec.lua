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
    local KE, GUIFrame, checkboxes, labels, headerToggle, calls, states

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

    -- Mirrors the RAW suppression shape (EUIWindows.lua: an
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
        labels = {}
        headerToggle = nil

        GUIFrame = {
            registeredContent = {},
            -- GUI-BlizzardFrames.lua registers its nested sub-row ids at FILE
            -- SCOPE, so this has to exist before the load.
            nestedTabOwner = {},
            pendingNestedTab = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            RegisterTabbedContent = function() end,
            RegisterNestedTabs = function(self, ownerId, nestedIds)
                for _, nestedId in ipairs(nestedIds) do
                    self.nestedTabOwner[nestedId] = ownerId
                end
            end,
            CreateCard = function()
                local card = { content = {} }
                function card:AddRow() end
                function card:AddLabel(text) labels[#labels + 1] = text end
                -- The real AddNote (GUI-Core.lua) is AddLabel plus an
                -- accent-coloured lead-in, so it records the same way.
                function card:AddNote(text)
                    return self:AddLabel(KE:ColorTextByTheme("-") .. " " .. text)
                end
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
            -- The Frame Skins card carries one dropdown (the Group Finder role
            -- icon style). Nothing here asserts on it; it only has to exist so
            -- the builder runs to the grid below.
            CreateDropdown = function(_, _, label, config)
                return { label = label, value = config.value, callback = config.callback }
            end,
            CreateCompactCheckbox = function(_, _, label, config)
                local checkbox = {
                    label = label,
                    tooltip = config.tooltip,
                    value = config.value,
                    callback = config.callback,
                    enabled = not config.disabled,
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
            FlagReloadNeeded = function() end,
            -- GUI-BlizzardFrames.lua reads `KE.LSM or LibStub(...)` at file
            -- scope now that it builds a font dropdown. HashTable is enough
            -- shape for the builder to iterate; the sibling
            -- GUI-BlizzardMessages.lua gets away with `LSM = {}` because it
            -- never calls HashTable.
            LSM = { HashTable = function() return {} end },
            -- The accent-coloured lead-in on this page's notes. Identity here:
            -- the colour is a look, and no assertion reads it.
            ColorTextByTheme = function(_, text) return text end,
        }
        -- ContextMenus' onToggle calls KitnEssentials:EnableModule /
        -- :DisableModule, so the addon object has to exist before the file
        -- loads and before any bulk toggle runs.
        helpers.installAddonShim()
        _G.KitnEssentials.EnableModule = function() end
        _G.KitnEssentials.DisableModule = function() end
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua", KE)
    end)

    -- Invokes the REAL registered content builder for the Frames tab.
    local function buildFrames()
        GUIFrame.registeredContent["SkinBlizzardFramesFrames"](nil, 0)
    end

    -- The Addon Skins tab, which is a separate builder over a separate list.
    -- Both share BuildSoloRows / BuildCheckGrid, so a change made for one can
    -- break the other silently -- this is the only route that would see it.
    -- AddonInstalled short-circuits to true when C_AddOns is absent
    -- (GUI-BlizzardFrames.lua), and this spec installs no such global,
    -- so every addon row reads installed here.
    local function buildAddons()
        GUIFrame.registeredContent["SkinBlizzardFramesAddons"](nil, 0)
    end

    -- The grid's Achievements cell. FRAME_SKINS is sorted by display name,
    -- "Achievements" sorts first, and this list carries no soloRow entry, so it
    -- is the first widget built. Named rather than written as a bare 1, because
    -- flagging any entry soloRow would push it down and the reason should stay
    -- attached to the number.
    local ACHIEVEMENT_CELL = 1

    describe("row rendering across all three states (same key: Achievement)", function()
        it("none: renders unchanged, no tooltip, not disabled", function()
            buildFrames()
            assert.equal("Achievements", checkboxes[ACHIEVEMENT_CELL].label)
            assert.is_nil(checkboxes[ACHIEVEMENT_CELL].tooltip)
            assert.is_true(checkboxes[ACHIEVEMENT_CELL].enabled)
        end)

        it("full: keeps the plain name, sets the suppression tooltip, disables", function()
            seedFull("Achievement")
            buildFrames()
            -- The marker moved OUT of the label: at three columns a suffix
            -- clips. Greying plus the note line carry it now.
            assert.equal("Achievements", checkboxes[ACHIEVEMENT_CELL].label)
            assert.equal(
                "EllesmereUI already skins this window, so KitnEssentials leaves it alone. Turn EllesmereUI's window skin off to use this one.",
                checkboxes[ACHIEVEMENT_CELL].tooltip)
            assert.is_false(checkboxes[ACHIEVEMENT_CELL].enabled)
        end)

        it("partial: marks with an asterisk, keeps the map's tooltip, stays enabled", function()
            seedPartial("Achievement", nil, "Achievements (EllesmereUI: dashboard only)", "Custom partial tooltip text")
            buildFrames()
            -- partialLabel is deliberately IGNORED now -- it is 37 characters at
            -- its longest and cannot fit a three-column cell. The tooltip still
            -- comes from the map verbatim.
            assert.equal("Achievements *", checkboxes[ACHIEVEMENT_CELL].label)
            assert.equal("Custom partial tooltip text", checkboxes[ACHIEVEMENT_CELL].tooltip)
            -- The negative assertion the whole feature exists for: a partial row
            -- must NOT be disabled.
            assert.is_true(checkboxes[ACHIEVEMENT_CELL].enabled)
        end)

        it("partial with no map tooltip: falls back to a generic one, never nil", function()
            seedPartial("Achievement")
            buildFrames()
            assert.equal("Achievements *", checkboxes[ACHIEVEMENT_CELL].label)
            -- The fallback wording is PARTIAL-specific, not the "full"
            -- suppression tooltip -- that one claims KitnEssentials leaves the
            -- window alone entirely, which is false next to a live, clickable
            -- partial row.
            assert.equal(
                "EllesmereUI covers part of this window group. This toggle still controls the rest.",
                checkboxes[ACHIEVEMENT_CELL].tooltip)
            assert.is_true(checkboxes[ACHIEVEMENT_CELL].enabled)
        end)
    end)

    describe("header anyOn, in isolation", function()
        -- A metatable default of `false` models "every row off" without
        -- hardcoding the full FRAME_SKINS key list (77 entries) -- only the
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
            -- Achievements sorts first, so seeding it full makes AnySuppressed
            -- return on its very first entry. Without that, AnySuppressed walks
            -- the whole list and puts WorldMap in `calls` by itself, and this
            -- assertion would pass with BuildCheckGrid deleted entirely.
            seedFull("Achievement")
            -- Default db.Skins (empty) otherwise: the any-on loop stops early
            -- too. So WorldMap in `calls` can only have come from the grid.
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
    -- Context Menus is the one FRAME_SKINS row that answers through isOn /
    -- onToggle instead of db.Skins. The failure this pins: dropping it from the
    -- table, or special-casing it out of the shared paths, would take it out of
    -- the header any-on read and the bulk toggle, so the master switch would
    -- silently skip one control.
    describe("Context Menus is reached by every shared path", function()
        it("renders exactly once, in the grid, carrying its own tooltip", function()
            buildFrames()

            local seen, row = 0, nil
            for _, cb in ipairs(checkboxes) do
                if cb.label == "Context Menus" then
                    seen = seen + 1
                    row = cb
                end
            end
            assert.equal(1, seen)
            -- The explanation moved off the label and into the tooltip when the
            -- label was shortened to fit a three-column cell.
            assert.equal("Skins right-click and dropdown menus.", row.tooltip)
        end)

        it("the bulk toggle reaches it", function()
            -- ContextMenus carries onToggle, so SetEntry never writes db.Skins
            -- for it -- the observable is the module flag its onToggle writes.
            KE.db.profile.Skinning.ContextMenus = { Enabled = true }
            buildFrames()
            headerToggle.callback(false)
            assert.is_false(KE.db.profile.Skinning.ContextMenus.Enabled)
        end)

        it("positive control: bulk-on turns it back on", function()
            KE.db.profile.Skinning.ContextMenus = { Enabled = false }
            buildFrames()
            headerToggle.callback(true)
            assert.is_true(KE.db.profile.Skinning.ContextMenus.Enabled)
        end)

        -- The other half of membership, and the half the two above cannot see:
        -- the header's any-on READ. A Context Menus dropped from FRAME_SKINS
        -- would still pass the bulk-toggle examples if it were toggled by some
        -- other path, but the header would stop noticing it was on.
        it("the any-on read reaches it: on alone, the header reads on", function()
            KE.db.profile.Skinning.ContextMenus = { Enabled = true }
            -- Every ordinary row off. ContextMenus ignores db.Skins entirely --
            -- it answers through isOn -- so it is the only member left that can
            -- make anyOn true.
            KE.db.profile.Skinning.BlizzardFrames =
                freshDB(setmetatable({}, { __index = function() return false end }))
            buildFrames()
            assert.is_true(headerToggle.anyOn)
        end)

        it("positive control: with it off too, the header reads off", function()
            KE.db.profile.Skinning.ContextMenus = { Enabled = false }
            KE.db.profile.Skinning.BlizzardFrames =
                freshDB(setmetatable({}, { __index = function() return false end }))
            buildFrames()
            assert.is_false(headerToggle.anyOn)
        end)
    end)
    describe("the EllesmereUI note line", function()
        local NOTE = "Greyed windows are already skinned by EllesmereUI. Windows marked with * are partly covered, and their toggle still controls the rest. Hover either for detail."

        -- Substring, not equality: the page's notes carry an accent-coloured
        -- lead-in, and asserting the whole decorated string would make this
        -- spec fail on a styling change it has no opinion about.
        local function containsLabel(text)
            for _, l in ipairs(labels) do
                if type(l) == "string" and l:find(text, 1, true) then return true end
            end
            return false
        end

        it("is absent when no row is suppressed", function()
            buildFrames()
            assert.is_false(containsLabel(NOTE))
        end)

        it("appears when a row is fully suppressed", function()
            seedFull("Achievement")
            buildFrames()
            assert.is_true(containsLabel(NOTE))
        end)

        it("appears when a row is only partly suppressed", function()
            seedPartial("Achievement")
            buildFrames()
            assert.is_true(containsLabel(NOTE))
        end)
    end)
    -- Ace3 is the Addon Skins solo row: it renders above the grid via
    -- BuildSoloRows, exactly as Context Menus used to. Same failure to pin --
    -- taking it out of ADDON_SKINS to stop the grid drawing it would also take
    -- it out of the header any-on read and the bulk toggle, and the master
    -- switch would silently skip one control.
    describe("Ace3 stays an ADDON_SKINS member while rendering outside the grid", function()
        local ACE_LABEL = "Addon Config Windows (AceGUI)"

        local function addonCheckboxLabels()
            local out = {}
            for _, cb in ipairs(checkboxes) do out[#out + 1] = cb.label end
            return out
        end

        it("renders exactly once, as the first widget, above the grid", function()
            buildAddons()
            assert.equal(ACE_LABEL, checkboxes[1].label)

            local seen = 0
            for _, label in ipairs(addonCheckboxLabels()) do
                if label == ACE_LABEL then seen = seen + 1 end
            end
            assert.equal(1, seen)
        end)

        it("the any-on read reaches it: on alone, the header reads on", function()
            -- Every other addon row off. Ace3 needs a REAL stored value, not an
            -- absent key: the metatable default answers false for anything
            -- missing, and EntryIsOn reads `skins[key] ~= false`, so leaving it
            -- unset would read off like the rest. With it on it is the only
            -- member that can make anyOn true.
            KE.db.profile.Skinning.BlizzardFrames = freshDB(setmetatable(
                { Ace3 = true },
                { __index = function() return false end }))
            buildAddons()
            assert.is_true(headerToggle.anyOn)
        end)

        it("positive control: with Ace3 off too, the header reads off", function()
            KE.db.profile.Skinning.BlizzardFrames = freshDB(setmetatable(
                { Ace3 = false },
                { __index = function() return false end }))
            buildAddons()
            assert.is_false(headerToggle.anyOn)
        end)

        it("the bulk toggle writes it", function()
            KE.db.profile.Skinning.BlizzardFrames = freshDB({})
            buildAddons()
            headerToggle.callback(false)
            -- SetEntry stores false for off, nil for on.
            assert.is_false(KE.db.profile.Skinning.BlizzardFrames.Skins.Ace3)

            headerToggle.callback(true)
            assert.is_nil(KE.db.profile.Skinning.BlizzardFrames.Skins.Ace3)
        end)
    end)
end)

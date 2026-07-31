local loader = require("dev.spec._ke_loader")

describe("EUIWindows", function()
    -- Builds the env table the pure resolver takes. `styles` maps an
    -- EllesmereUI window key to what GetBlizzWindowStyle would answer.
    -- Sentinel, not `opts.version or "8.6.4"`. With the `or` form, passing
    -- version = nil to model an unreadable EllesmereUI silently yields
    -- "8.6.4" and the unreadable-version test asserts nothing.
    local NO_VERSION = {}

    local function env(opts)
        opts = opts or {}
        local version = opts.version
        if version == nil then version = "8.6.4" end
        if version == NO_VERSION then version = nil end
        return {
            loaded = opts.loaded ~= false,
            version = version,
            getStyle = function(key)
                if opts.styles and opts.styles[key] ~= nil then
                    return opts.styles[key]
                end
                -- Models EllesmereUI's own fail-open default
                -- (EllesmereUIBlizzardSkin.lua:76-84): anything not
                -- explicitly off answers "eui".
                return "eui"
            end,
        }
    end

    describe("CompareVersion", function()
        it("orders by numeric segment, not by string", function()
            local _, KE = loader.loadEUIWindows()
            -- "8.6.10" > "8.6.4" numerically but < as a string. Getting this
            -- wrong would silently un-suppress three windows on a future
            -- EllesmereUI.
            assert.equal(1, KE.Skins.CompareVersion("8.6.10", "8.6.4"))
            assert.equal(-1, KE.Skins.CompareVersion("8.5.9", "8.6.4"))
            assert.equal(0, KE.Skins.CompareVersion("8.6.4", "8.6.4"))
        end)

        it("treats a missing or unparseable version as lower", function()
            local _, KE = loader.loadEUIWindows()
            assert.equal(-1, KE.Skins.CompareVersion(nil, "8.6.4"))
            assert.equal(-1, KE.Skins.CompareVersion("", "8.6.4"))
            assert.equal(-1, KE.Skins.CompareVersion("v-unknown", "8.6.4"))
        end)

        it("tolerates differing segment counts", function()
            local _, KE = loader.loadEUIWindows()
            assert.equal(-1, KE.Skins.CompareVersion("8.6", "8.6.1"))
            assert.equal(0, KE.Skins.CompareVersion("8.6.0", "8.6"))
        end)
    end)

    describe("BuildSkinSuppressionSet", function()
        it("suppresses a skin EllesmereUI owns", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env())
            assert.equal("merchant", set.Merchant)
            assert.equal("mail", set.Mail)
        end)

        it("maps every skin behind a multi-skin window", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env())
            -- EllesmereUI's charsheet pack covers three of our skins.
            assert.equal("charsheet", set.Character)
            assert.equal("charsheet", set.Currency)
            assert.equal("charsheet", set.Reputation)
        end)

        it("leaves a window EllesmereUI has turned off", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env({
                styles = { merchant = "off" },
            }))
            assert.is_nil(set.Merchant)
            assert.equal("mail", set.Mail)
        end)

        it("treats the modern style as owned", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env({
                styles = { merchant = "modern" },
            }))
            assert.equal("merchant", set.Merchant)
        end)

        it("suppresses nothing when EllesmereUI is absent", function()
            local _, KE = loader.loadEUIWindows()
            assert.same({}, KE:BuildSkinSuppressionSet(env({ loaded = false })))
        end)

        it("suppresses nothing without a usable getStyle", function()
            local _, KE = loader.loadEUIWindows()
            assert.same({}, KE:BuildSkinSuppressionSet({
                loaded = true, version = "8.6.4", getStyle = nil,
            }))
        end)

        it("suppresses nothing for a malformed env", function()
            local _, KE = loader.loadEUIWindows()
            assert.same({}, KE:BuildSkinSuppressionSet(nil))
            assert.same({}, KE:BuildSkinSuppressionSet("nonsense"))
        end)

        -- The fail-open trap. GetBlizzWindowStyle answers "eui" for a key it
        -- has never heard of, so on EllesmereUI 8.5.9 -- which predates
        -- `itemupgrade` -- asking about it claims ownership of a window it
        -- does not skin. The `since` gate is the only thing standing between
        -- that and one silently missing skin. `loottoast` is gated the same
        -- way -- see the split-specific cases below. (`loot` carries no row
        -- at all -- see "map integrity" below.)
        it("ignores an entry newer than the installed EllesmereUI", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env({ version = "8.5.9" }))
            assert.is_nil(set.ItemUpgrade)
            -- Everything without a `since` still resolves normally.
            assert.equal("merchant", set.Merchant)
        end)

        it("honours an entry once the installed version reaches it", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env({ version = "8.6.4" }))
            assert.equal("itemupgrade", set.ItemUpgrade)
        end)

        it("ignores every gated entry when the version is unreadable", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env({ version = NO_VERSION }))
            assert.is_nil(set.ItemUpgrade)
            assert.equal("merchant", set.Merchant)
        end)

        it("never suppresses our four-family loot window key", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env())
            -- Positive control: with every style answering "eui" the sibling
            -- toast key IS suppressed, so the negative below cannot be passing
            -- against a resolver that suppresses nothing at all.
            assert.equal("loottoast", set.LootToast)
            -- EllesmereUI's loot pack touches only _G.LootFrame; our `Loot`
            -- key covers four families, so it is never suppressed whole.
            assert.is_nil(set.Loot)
        end)

        it("never suppresses the non-toast alert popups", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env())
            -- Positive control first: with every style answering "eui" the
            -- toast key IS suppressed, so a resolver that suppressed nothing
            -- at all could not satisfy the negative below.
            assert.equal("loottoast", set.LootToast)
            -- EllesmereUI leaves achievement and other alert styles alone,
            -- so our nineteen-system `Alerts` key must survive.
            assert.is_nil(set.Alerts)
        end)

        it("leaves the toast key to us on EllesmereUI 8.6.3", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env({ version = "8.6.3" }))
            -- The key does not exist before 8.6.4, and GetBlizzWindowStyle
            -- fails OPEN, so without the gate an 8.6.3 client would answer
            -- "eui" for it and silently drop our skin.
            assert.is_nil(set.LootToast)
            -- Positive control: an ungated row still resolves on 8.6.3.
            assert.equal("merchant", set.Merchant)
        end)
    end)

    describe("map integrity", function()
        it("names each EllesmereUI window key at most once", function()
            local _, KE = loader.loadEUIWindows()
            local seen = {}
            for _, entry in ipairs(KE.Skins.WINDOW_MAP) do
                assert.is_nil(seen[entry.euiKey], "duplicate " .. entry.euiKey)
                seen[entry.euiKey] = true
            end
        end)

        it("gives every entry at least one skin key", function()
            local _, KE = loader.loadEUIWindows()
            for _, entry in ipairs(KE.Skins.WINDOW_MAP) do
                assert.is_table(entry.skins, entry.euiKey .. " has no skins")
                assert.is_true(#entry.skins > 0, entry.euiKey .. " has no skins")
            end
        end)

        it("parses every since value", function()
            local _, KE = loader.loadEUIWindows()
            for _, entry in ipairs(KE.Skins.WINDOW_MAP) do
                if entry.since then
                    assert.is_true(KE.Skins.CompareVersion(entry.since, "0") > 0,
                        entry.euiKey .. " has an unparseable since")
                end
            end
        end)

        it("has no loot row, and maps loottoast to the split key only", function()
            local _, KE = loader.loadEUIWindows()
            local byKey = {}
            for _, entry in ipairs(KE.Skins.WINDOW_MAP) do
                -- EllesmereUI's loot pack touches only _G.LootFrame; our `Loot`
                -- key covers four families. An unfiltered row here silently
                -- costs three (a6-3a:121-125). It must never come back.
                assert.are_not.equal("loot", entry.euiKey)
                byKey[entry.euiKey] = entry
            end
            -- Positive control: the sibling row DOES exist, so the assertion
            -- above cannot be passing merely because the map is empty.
            assert.is_table(byKey.loottoast)
            -- And it points at the split key, never back at the whole
            -- twenty-five-system `Alerts` key it used to carry.
            assert.same({ "LootToast" }, byKey.loottoast.skins)
        end)

        it("repoints inspectrecipe onto InspectRecipe without touching professions", function()
            -- A repoint that edited the wrong row (or both) would pass a
            -- single-sided check; this asserts both rows in one test.
            local _, KE = loader.loadEUIWindows()
            local byKey = {}
            for _, entry in ipairs(KE.Skins.WINDOW_MAP) do byKey[entry.euiKey] = entry end
            assert.same({ "InspectRecipe" }, byKey.inspectrecipe.skins)
            assert.same({ "Professions" }, byKey.professions.skins)
        end)

        it("keeps `addons` to exactly the housing and delves rows", function()
            local _, KE = loader.loadEUIWindows()
            local sawHousing, sawDelves = false, false
            for _, entry in ipairs(KE.Skins.WINDOW_MAP) do
                if entry.euiKey == "housing" then
                    sawHousing = true
                    assert.same({ "Blizzard_HousingDashboard" }, entry.addons)
                elseif entry.euiKey == "delves" then
                    sawDelves = true
                    assert.same({ "Blizzard_DelvesCompanionConfiguration" }, entry.addons)
                else
                    assert.is_nil(entry.addons, entry.euiKey .. " should not have grown an addons filter")
                end
            end
            -- Positive control: without this, deleting either row entirely
            -- leaves the branch above unreached and the test still green.
            assert.is_true(sawHousing, "housing row is missing")
            assert.is_true(sawDelves, "delves row is missing")
        end)
    end)

    describe("suppression accessors", function()
        -- Test through the production seam: every case below is fed the
        -- real BuildSkinSuppressionSet output, never a hand-seeded fixture.
        it("resolves the accessor triad atomically off one real suppression set", function()
            local _, KE = loader.loadEUIWindows()
            KE.Skins.suppressed = KE:BuildSkinSuppressionSet(env())

            -- housing (filtered row): named addon -> suppressed.
            assert.equal("housing", KE.Skins.GetSuppression("Housing", "Blizzard_HousingDashboard"))
            -- filtered row: an addon it does not name -> nil.
            assert.is_nil(KE.Skins.GetSuppression("Housing", "SomeOtherAddon"))
            -- filtered row: nil addon -> nil (opposite of the unfiltered case
            -- below -- an early registration cannot match a named filter).
            assert.is_nil(KE.Skins.GetSuppression("Housing", nil))
            -- merchant (unfiltered row): nil addon -> suppressed, because an
            -- unfiltered row covers the whole key, early registrations too.
            assert.equal("merchant", KE.Skins.GetSuppression("Merchant", nil))
            -- unfiltered row: any addon -> still suppressed.
            assert.equal("merchant", KE.Skins.GetSuppression("Merchant", "AnyAddon"))

            -- GetSuppressionState across three different keys in the SAME
            -- env -- an always-"none" implementation fails two of these.
            assert.equal("partial", (KE.Skins.GetSuppressionState("Housing")))
            assert.equal("full", (KE.Skins.GetSuppressionState("Merchant")))
            -- TalentLoadoutsEx has no WINDOW_MAP row at all (see the comment
            -- above `playerspells`), so it can never appear in the set.
            assert.equal("none", (KE.Skins.GetSuppressionState("TalentLoadoutsEx")))
        end)

        it("gates ItemUpgrade through the accessor, not only the set", function()
            -- An accessor that reads WINDOW_MAP directly instead of the
            -- resolved set would pass every other case while ignoring the
            -- `since` gate entirely -- this runs the gate through
            -- GetSuppression/GetSuppressionState, not BuildSkinSuppressionSet.
            local _, KE = loader.loadEUIWindows()

            KE.Skins.suppressed = KE:BuildSkinSuppressionSet(env({ version = "8.6.3" }))
            assert.is_nil(KE.Skins.GetSuppression("ItemUpgrade", "Blizzard_ItemUpgradeUI"))
            assert.equal("none", (KE.Skins.GetSuppressionState("ItemUpgrade")))
            -- Positive control on the SAME env: proves the env resolves
            -- something at all, so the nils above aren't from an empty set.
            assert.equal("merchant", KE.Skins.GetSuppression("Merchant", nil))

            KE.Skins.suppressed = KE:BuildSkinSuppressionSet(env({ version = NO_VERSION }))
            assert.is_nil(KE.Skins.GetSuppression("ItemUpgrade", "Blizzard_ItemUpgradeUI"))
            assert.equal("none", (KE.Skins.GetSuppressionState("ItemUpgrade")))
            assert.equal("merchant", KE.Skins.GetSuppression("Merchant", nil))
        end)
    end)

    describe("the diagnostics seam (SkinAPI.DebugVerify / DebugRerun)", function()
        -- Housing has no registrations of its own until a much later task,
        -- so a test that only calls the two functions never reaches either
        -- concatenation: DebugVerify iterates S.skinRegistrations, which has
        -- no entry for a key nothing ever registered (SkinAPI.lua:2798-2800),
        -- and DebugRerun's own lookup reads that same table
        -- (SkinAPI.lua:2855-2856), not skinIndex. Both require a real
        -- dispatch, so this registers a synthetic skin and runs it through
        -- the real path
        -- (S:Register + BF:RunForAddon, same as skinapi_spec.lua's
        -- "holds an addon-registered skin" case) on the composed loader,
        -- which is the only loader where a real filtered suppression record
        -- and the real dispatcher share one KE.
        it("prints the owning euiKey through both concatenation sites for a dispatched, suppressed skin", function()
            local KE = loader.loadSkinAPI_EUIWindows()
            local S = KE.Skins

            S.suppressed = KE:BuildSkinSuppressionSet(env())
            S:Register("Blizzard_HousingDashboard", function() end, "Housing")
            local BF = _G.KitnEssentials:GetModule("BlizzardFrames")
            BF:RunForAddon("Blizzard_HousingDashboard")
            -- "suppressed", not "disabled" (Task 0B): a key whose registration
            -- never dispatched aggregates to "pending", so this value is only
            -- reachable once a record actually went through dispatch and hit
            -- the suppression branch -- still proof of a real dispatch, and a
            -- stronger one than the old "disabled" (which a merely-undispatched
            -- key could never produce either, but read the same as the user's
            -- own opt-out).
            assert.equal("suppressed", S.skinStatus.Housing)

            local printed = {}
            local realPrint = _G.print
            _G.print = function(msg) printed[#printed + 1] = msg end
            local ok = pcall(function()
                S.DebugVerify()
                S.DebugRerun("Housing")
            end)
            _G.print = realPrint
            assert.is_true(ok, "DebugVerify/DebugRerun raised an error -- likely a raw table concatenation")

            local verifyLine, rerunLine
            for _, line in ipairs(printed) do
                if line:find("Housing", 1, true) and line:find("suppressed by EllesmereUI (", 1, true) then
                    verifyLine = verifyLine or line
                end
                if line:find("Rerunning it would double", 1, true) then
                    rerunLine = line
                end
            end

            assert.truthy(verifyLine, "DebugVerify did not print a suppressed line for Housing")
            assert.truthy(verifyLine:find("suppressed by EllesmereUI (housing)", 1, true))
            assert.truthy(rerunLine, "DebugRerun did not print its refusal message")
            assert.truthy(rerunLine:find("suppressed by EllesmereUI (housing)", 1, true))
        end)
    end)
end)

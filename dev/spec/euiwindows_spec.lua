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
        -- has never heard of, so on EllesmereUI 8.5.9 -- which has no `loot`
        -- key -- asking about `loot` claims ownership of a window it does not
        -- skin. The `since` gate is the only thing standing between that and
        -- three silently missing skins.
        it("ignores an entry newer than the installed EllesmereUI", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env({ version = "8.5.9" }))
            assert.is_nil(set.Loot)
            assert.is_nil(set.Alerts)
            assert.is_nil(set.ItemUpgrade)
            -- Everything without a `since` still resolves normally.
            assert.equal("merchant", set.Merchant)
        end)

        it("honours an entry once the installed version reaches it", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env({ version = "8.6.4" }))
            assert.equal("loot", set.Loot)
            assert.equal("loottoast", set.Alerts)
            assert.equal("itemupgrade", set.ItemUpgrade)
        end)

        it("ignores every gated entry when the version is unreadable", function()
            local _, KE = loader.loadEUIWindows()
            local set = KE:BuildSkinSuppressionSet(env({ version = NO_VERSION }))
            assert.is_nil(set.Loot)
            assert.is_nil(set.Alerts)
            assert.is_nil(set.ItemUpgrade)
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
    end)
end)

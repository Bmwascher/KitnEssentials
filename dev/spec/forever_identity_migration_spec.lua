-- Tier 1: KE's ownership decision for account-wide character records
-- (Core/Identity.lua). AceDB's own key construction is not repeated here;
-- each case hands in the key AceDB would have produced.
local helpers = require("dev.spec._helpers")

local SECRET = "<<declared secret>>"

local function load()
    return helpers.loadModule("Core/Identity.lua", {
        IsSecretValue = function(_, v) return v == SECRET end,
    })
end

local REGIONAL = { charKey = "Bob Smith", name = "Bob", regional = true }
local RETAIL = { charKey = "Bob - Realm", regional = false }

describe("Core/Identity.lua", function()
    after_each(function()
        _G.UnitNameUnmodified = nil
        _G.RegionalUniqueNamesEnabled = nil
        _G.Constants = nil
    end)

    it("never attributes another identity's record to a character sharing its first name", function()
        local KE = load()
        for _, row in ipairs({
            { key = "Bob Smith",   identity = REGIONAL, want = "owned" },
            { key = "Bob Jones",   identity = REGIONAL, want = "unresolved" },
            { key = "Bob",         identity = REGIONAL, want = "unresolved" },
            { key = "Alice Smith", identity = REGIONAL, want = "other" },
            { key = "Bob - Other", identity = RETAIL,   want = "other" },
        }) do
            assert.equals(row.want, KE:ClassifyLegacyCharacterRecord(row.key, {}, row.identity), row.key)
        end
    end)

    it("refuses attribution without complete evidence, a sole legacy record included", function()
        local KE = load()
        for _, row in ipairs({
            { name = "sole legacy record", key = "Bob - Classic Beta PvP 2", entry = {},  identity = REGIONAL },
            { name = "secret key",         key = SECRET,                     entry = {},  identity = REGIONAL },
            { name = "no identity",        key = "Alice Smith",              entry = {},  identity = nil },
            { name = "no record table",    key = "Alice Smith",              entry = "x", identity = REGIONAL },
        }) do
            assert.equals("unresolved",
                KE:ClassifyLegacyCharacterRecord(row.key, row.entry, row.identity), row.name)
        end

        _G.RegionalUniqueNamesEnabled = function() return true end
        for _, row in ipairs({
            { name = "no database", db = nil,                               unitName = "Bob" },
            { name = "secret name", db = { keys = { char = "Bob Smith" } }, unitName = SECRET },
            { name = "empty name",  db = { keys = { char = "Bob Smith" } }, unitName = "" },
        }) do
            KE.db = row.db
            _G.UnitNameUnmodified = function() return row.unitName end
            assert.is_nil(KE:GetPlayerIdentityParts(), row.name)
        end
    end)

    -- The client's own full name for a first name and surname. A non-space
    -- separator in the constant row proves the constant is read.
    it("joins a first name and surname the way the client spells a full name", function()
        local KE = load()
        for _, row in ipairs({
            { why = "separator constant",    sep = "_", name = "Bob",       surname = "Smith", want = "Bob_Smith" },
            { why = "no constant: a space",  sep = nil, name = "Bob",       surname = "Smith", want = "Bob Smith" },
            { why = "no surname",            sep = nil, name = "Bob",       surname = nil,     want = "Bob" },
            { why = "empty surname",         sep = nil, name = "Bob",       surname = "",      want = "Bob" },
            { why = "secret surname",        sep = nil, name = "Bob",       surname = SECRET,  want = "Bob" },
            { why = "already joined",        sep = nil, name = "Bob Smith", surname = "Smith", want = "Bob Smith" },
            { why = "secret name",           sep = nil, name = SECRET,      surname = "Smith", want = nil },
            { why = "empty name",            sep = nil, name = "",          surname = "Smith", want = nil },
        }) do
            if row.sep then
                _G.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = row.sep } }
            else
                _G.Constants = nil
            end
            assert.equals(row.want, KE:JoinCharacterName(row.name, row.surname), row.why)
        end
    end)
end)

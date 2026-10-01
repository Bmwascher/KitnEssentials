-- Tier 1: the chat history move into the per-character store
-- (Core/Defaults.lua, KE:MigrateChatHistoryToCharStore). It reads AceDB's raw
-- account table, so the spec builds that table by hand.
local helpers = require("dev.spec._helpers")

local ME = "Me - Realm"
local ALT = "Alt - Realm"

local function migrate(row)
    _G.KitnEssentialsCharDB = row.store
    local KE = helpers.loadModule("Core/Defaults.lua")
    KE.db = { sv = { char = row.account }, keys = { char = ME } }
    for _ = 1, row.runs or 1 do
        KE:MigrateChatHistoryToCharStore()
    end
    return KE.db.sv, _G.KitnEssentialsCharDB
end

describe("chat history move to the per-character store", function()
    after_each(function()
        _G.KitnEssentialsCharDB = nil
    end)

    it("moves the current character's rows once and touches nothing else", function()
        local own = { { "hi", event = "CHAT_MSG_SAY", time = 5 } }
        local kept = { { "kept", event = "CHAT_MSG_SAY", time = 9 } }
        local alt = { ChatHistory = { { "yo", event = "CHAT_MSG_SAY", time = 1 } } }
        local rows = {
            {
                name = "copies own rows and deletes them from the account file",
                account = { [ME] = { ChatHistory = own, ChatTypingHistory = { "/say hi" } } },
                check = function(sv, store)
                    assert.equals(own, store.ChatHistory)
                    assert.same({ "/say hi" }, store.ChatTypingHistory)
                    assert.is_nil(sv.char)
                end,
            },
            {
                name = "deletes own rows only",
                account = { [ME] = { ChatHistory = own }, [ALT] = alt },
                check = function(sv, store)
                    assert.equals(own, store.ChatHistory)
                    assert.is_nil(sv.char[ME])
                    assert.equals(alt, sv.char[ALT])
                    assert.equals(1, #alt.ChatHistory)
                end,
            },
            {
                name = "a second run moves nothing more",
                account = { [ME] = { ChatHistory = own }, [ALT] = alt },
                runs = 2,
                check = function(sv, store)
                    assert.equals(own, store.ChatHistory)
                    assert.is_nil(store.ChatTypingHistory)
                    assert.equals(alt, sv.char[ALT])
                end,
            },
            {
                name = "an empty character gets no store",
                account = { [ME] = { ChatHistory = {}, ChatTypingHistory = {} } },
                check = function(sv, store)
                    assert.is_nil(store)
                    assert.is_nil(sv.char)
                end,
            },
            {
                name = "a filled store is kept over the account rows",
                account = { [ME] = { ChatHistory = own } },
                store = { ChatHistory = kept },
                check = function(sv, store)
                    assert.equals(kept, store.ChatHistory)
                    assert.equals(1, #kept)
                    assert.is_nil(sv.char)
                end,
            },
        }
        for _, row in ipairs(rows) do
            local sv, store = migrate(row)
            local ok, err = pcall(row.check, sv, store)
            assert(ok, row.name .. ": " .. tostring(err))
        end
    end)
end)

describe("stale chat cleanup", function()
    after_each(function()
        _G.GetServerTime = nil
    end)

    it("clears only other characters whose newest dated line is over 90 days old", function()
        local DAY = 24 * 60 * 60
        local NOW = 1000 * DAY
        _G.GetServerTime = function() return NOW end
        local printed = {}
        local KE = helpers.loadModule("Core/Defaults.lua", {
            IsSecretValue = function() return false end,
            Print = function(_, msg) printed[#printed + 1] = msg end,
        })
        local account = {
            [ME] = { ChatHistory = { { "mine", time = NOW - 200 * DAY } } },
            ["Old - Realm"] = {
                ChatHistory = { { "a", time = NOW - 120 * DAY }, { "b", time = NOW - 91 * DAY } },
                ChatTypingHistory = { "/say a" },
            },
            -- The recent row sits under a non-array key: every key is read.
            ["Recent - Realm"] = {
                ChatHistory = { { "a", time = NOW - 200 * DAY }, recent = { "b", time = NOW - 10 * DAY } },
            },
            -- One old dated row beside one undated row: the undated row keeps it.
            ["Undated - Realm"] = {
                ChatHistory = { { "a", time = NOW - 200 * DAY }, { "b" } },
                ChatTypingHistory = { "/say a" },
            },
        }
        KE.db = { sv = { char = account }, keys = { char = ME } }
        KE:ClearStaleChatHistory()
        assert.is_nil(account["Old - Realm"].ChatHistory)
        assert.is_nil(account["Old - Realm"].ChatTypingHistory)
        assert.is_table(account["Recent - Realm"].ChatHistory.recent)
        assert.equals(2, #account["Undated - Realm"].ChatHistory)
        assert.equals(1, #account["Undated - Realm"].ChatTypingHistory)
        assert.equals(1, #account[ME].ChatHistory)
        assert.same({ "Removed saved chat older than 90 days for 1 characters." }, printed)
    end)
end)

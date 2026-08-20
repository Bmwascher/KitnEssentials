local L = require("dev.spec._ke_loader")

local function inInstance()
    return function() return true, "party" end
end

local function secretIs(value)
    return function(v) return v == value end
end

describe("ChatHistory storage guards", function()
    it("stores an ordinary say message", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(1, #KE.db.char.ChatHistory)
        assert.equals("hello", KE.db.char.ChatHistory[1][1])
        assert.equals("CHAT_MSG_SAY", KE.db.char.ChatHistory[1].event)
        assert.equals(2000, KE.db.char.ChatHistory[1].time)
    end)

    it("refuses every message received inside an instance", function()
        local CH, KE = L.loadChatHistory({ IsInInstance = inInstance() })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        CH:SaveChatHistory("CHAT_MSG_PARTY", "pull", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses when the instance check throws", function()
        local CH, KE = L.loadChatHistory({
            IsInInstance = function() error("boom") end,
        })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses when the instance check returns nil", function()
        local CH, KE = L.loadChatHistory({ IsInInstance = function() return nil end })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses when the instance check returns a secret", function()
        local flag = {}
        local CH, KE = L.loadChatHistory({
            IsInInstance = function() return flag, "none" end,
            issecretvalue = secretIs(flag),
        })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses a secret body", function()
        local CH, KE = L.loadChatHistory({ issecretvalue = secretIs("hello") })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses a secret sender even when the body is plain", function()
        local CH, KE = L.loadChatHistory({ issecretvalue = secretIs("Bob") })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses a row whose timestamp reads secret at capture time", function()
        -- The timestamp goes to disk like any other field, so it is refused at
        -- CAPTURE. RowIsReplayable checks it again on the way back out, but a
        -- check on read cannot unwrite a value that was already persisted.
        local stamp = {}
        local CH, KE = L.loadChatHistory({
            GetServerTime = function() return stamp end,
            issecretvalue = secretIs(stamp),
        })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("falls back to time() when the server clock returns no number", function()
        local CH, KE = L.loadChatHistory({
            GetServerTime = function() return nil end,
        })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(1000, KE.db.char.ChatHistory[1].time)
    end)

    it("refuses when the fallback clock reads secret", function()
        local stamp = {}
        local CH, KE = L.loadChatHistory({
            GetServerTime = function() return nil end,
            time = function() return stamp end,
            issecretvalue = secretIs(stamp),
        })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses when neither clock returns a number", function()
        local CH, KE = L.loadChatHistory({
            GetServerTime = function() return nil end,
            time = function() return "nownow" end,
        })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("falls back when the server clock is not installed at all", function()
        local CH, KE = L.loadChatHistory({ GetServerTime = false })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(1000, KE.db.char.ChatHistory[1].time)
    end)

    it("refuses when neither clock is installed", function()
        local CH, KE = L.loadChatHistory({ GetServerTime = false, time = false })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses a protected body", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_SAY", "hi |Kf123|k there", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("never puts a table on disk", function()
        local CH, KE = L.loadChatHistory()
        -- Position 3, so the table is followed by a real value and survives
        -- truncation as a stored slot rather than being trimmed off the tail.
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob", { globalName = "leak" }, "Common")
        local row = KE.db.char.ChatHistory[1]
        assert.equals("hello", row[1])
        assert.equals(false, row[3])
        assert.equals("Common", row[4])
    end)

    it("trims a trailing table off the row entirely", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob", { globalName = "leak" })
        local row = KE.db.char.ChatHistory[1]
        assert.equals(2, #row)
        assert.is_nil(row[3])
    end)

    it("refuses a type the user switched off", function()
        local CH, KE = L.loadChatHistory()
        KE.db.profile.Skinning.ChatHistory.ShowTypes.SAY = false
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses everything while the module is off", function()
        local CH, KE = L.loadChatHistory()
        KE.db.profile.Skinning.ChatHistory.Enabled = false
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses an event it does not cover", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_LOOT", "you get", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("refuses guild achievements, which the handler routes elsewhere", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_GUILD_ACHIEVEMENT", "earned", "Bob")
        assert.equals(0, #KE.db.char.ChatHistory)
    end)

    it("trims to the cap, dropping the oldest", function()
        local CH, KE = L.loadChatHistory()
        KE.db.profile.Skinning.ChatHistory.Size = 3
        for i = 1, 5 do CH:SaveChatHistory("CHAT_MSG_SAY", "m" .. i, "Bob") end
        local data = KE.db.char.ChatHistory
        assert.equals(3, #data)
        assert.equals("m3", data[1][1])
        assert.equals("m5", data[3][1])
    end)

    it("keeps exactly the number of rows the cap advertises", function()
        local CH, KE = L.loadChatHistory()
        KE.db.profile.Skinning.ChatHistory.Size = 4
        for i = 1, 4 do CH:SaveChatHistory("CHAT_MSG_SAY", "m" .. i, "Bob") end
        assert.equals(4, #KE.db.char.ChatHistory)
    end)

    it("packs nil holes as false so the row stays dense", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob", nil, nil, "Bob")
        local row = KE.db.char.ChatHistory[1]
        assert.equals(false, row[3])
        assert.equals("Bob", row[5])
    end)

    it("truncates the row at the last argument that carries anything", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.equals(2, #KE.db.char.ChatHistory[1])
    end)

    it("registers only the types the user has switched on", function()
        local CH, KE = L.loadChatHistory()
        KE.db.profile.Skinning.ChatHistory.ShowTypes.SAY = false
        local registered = {}
        CH.RegisterEvent = function(_, event) registered[event] = true end
        CH:RegisterHistoryEvents()
        assert.is_nil(registered.CHAT_MSG_SAY)
        assert.is_true(registered.CHAT_MSG_YELL)
    end)

    it("clears both stores", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        KE.db.char.ChatTypingHistory[1] = "/say hi"
        CH:ClearHistory()
        assert.equals(0, #KE.db.char.ChatHistory)
        assert.equals(0, #KE.db.char.ChatTypingHistory)
    end)
end)

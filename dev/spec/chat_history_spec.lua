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

describe("ChatHistory replay", function()
    local function fakeHandler()
        local calls = {}
        return {
            replaying = false,
            calls = calls,
            ChatFrame_MessageEventHandler = function(self, frame, event, ...)
                calls[#calls + 1] = {
                    frame = frame, event = event, args = { ... },
                    replayingAtCall = self.replaying,
                }
            end,
        }
    end

    local function withFrame(messageTypes)
        _G.ChatFrame1 = { messageTypeList = messageTypes }
        return _G.ChatFrame1
    end

    it("refuses a row whose stored body reads secret at replay time", function()
        local CH, KE = L.loadChatHistory({ issecretvalue = secretIs("hello") })
        KE.db.char.ChatHistory[1] = { "hello", "Bob", event = "CHAT_MSG_SAY", time = 5 }
        assert.is_false(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
    end)

    it("refuses a row whose stored sender reads secret at replay time", function()
        local CH, KE = L.loadChatHistory({ issecretvalue = secretIs("Bob") })
        KE.db.char.ChatHistory[1] = { "hello", "Bob", event = "CHAT_MSG_SAY", time = 5 }
        assert.is_false(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
    end)

    it("refuses a row whose stored timestamp reads secret at replay time", function()
        local stamp = {}
        local CH, KE = L.loadChatHistory({ issecretvalue = secretIs(stamp) })
        KE.db.char.ChatHistory[1] = { "hello", "Bob", event = "CHAT_MSG_SAY", time = stamp }
        assert.is_false(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
    end)

    it("does nothing while the chat skin is off", function()
        local CH, KE = L.loadChatHistory()
        KE.ChatMessageHandler = fakeHandler()
        withFrame({ "SAY" })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        CH.ChatSkinActive = function() return false end
        CH:DisplayChatHistory()

        assert.equals(0, #KE.ChatMessageHandler.calls)
    end)

    it("refuses a row whose type the user has since switched off", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        KE.db.profile.Skinning.ChatHistory.ShowTypes.SAY = false
        assert.is_false(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
    end)

    it("refuses a malformed row", function()
        local CH = L.loadChatHistory()
        assert.is_false(CH:RowIsReplayable("not a row"))
        assert.is_false(CH:RowIsReplayable(nil))
        assert.is_false(CH:RowIsReplayable({ "hello", "Bob" }))
        assert.is_false(CH:RowIsReplayable({ event = "CHAT_MSG_SAY" }))
    end)

    it("refuses a row with no usable timestamp", function()
        local CH = L.loadChatHistory()
        assert.is_false(CH:RowIsReplayable({ "hello", "Bob", event = "CHAT_MSG_SAY" }))
        assert.is_false(CH:RowIsReplayable({ "hello", "Bob", event = "CHAT_MSG_SAY", time = "5" }))
        assert.is_false(CH:RowIsReplayable({ "hello", "Bob", event = "CHAT_MSG_SAY", time = {} }))
    end)

    it("accepts an ordinary stored row", function()
        local CH, KE = L.loadChatHistory()
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        assert.is_true(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
    end)

    it("dispatches with the marker and the stored time", function()
        local CH, KE = L.loadChatHistory()
        KE.ChatMessageHandler = fakeHandler()
        local frame = withFrame({ "SAY" })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        CH:DisplayChatHistory()

        assert.equals(1, #KE.ChatMessageHandler.calls)
        local call = KE.ChatMessageHandler.calls[1]
        assert.equals(frame, call.frame)
        assert.equals("CHAT_MSG_SAY", call.event)
        assert.equals("hello", call.args[1])
        -- Seventeen stored positions, then false for the argument that is
        -- never stored, then the marker and the time.
        assert.equals(false, call.args[18])
        assert.equals("KE_ChatHistory", call.args[19])
        assert.equals(2000, call.args[20])
    end)

    it("sets the mute flag for the dispatch and clears it after", function()
        local CH, KE = L.loadChatHistory()
        KE.ChatMessageHandler = fakeHandler()
        withFrame({ "SAY" })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        CH:DisplayChatHistory()

        assert.is_true(KE.ChatMessageHandler.calls[1].replayingAtCall)
        assert.is_false(KE.ChatMessageHandler.replaying)
    end)

    it("dispatches a row to a frame once even when the type list repeats", function()
        local CH, KE = L.loadChatHistory()
        KE.ChatMessageHandler = fakeHandler()
        withFrame({ "SAY", "SAY" })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        CH:DisplayChatHistory()

        assert.equals(1, #KE.ChatMessageHandler.calls)
    end)

    it("skips a frame that does not carry the row's type", function()
        local CH, KE = L.loadChatHistory()
        KE.ChatMessageHandler = fakeHandler()
        withFrame({ "GUILD" })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        CH:DisplayChatHistory()

        assert.equals(0, #KE.ChatMessageHandler.calls)
    end)

    it("keeps going, surfaces the error, and clears the mute flag when one row throws", function()
        local CH, KE, _, caught = L.loadChatHistory()
        local seen = {}
        KE.ChatMessageHandler = {
            replaying = false,
            ChatFrame_MessageEventHandler = function(_, _, _, body)
                if body == "first" then error("boom") end
                seen[#seen + 1] = body
            end,
        }
        withFrame({ "SAY" })
        CH:SaveChatHistory("CHAT_MSG_SAY", "first", "Bob")
        CH:SaveChatHistory("CHAT_MSG_SAY", "second", "Bob")
        CH:DisplayChatHistory()

        -- The row after the throwing one still went out ...
        assert.equals(1, #seen)
        assert.equals("second", seen[1])
        -- ... the error was not swallowed ...
        assert.equals(1, #caught)
        -- ... and live chat is not left muted.
        assert.is_false(KE.ChatMessageHandler.replaying)
    end)

    it("skips a CHAT_FRAMES entry that is not a frame, and stays unmuted", function()
        -- CHAT_FRAMES is a Blizzard global any addon can append to. A number or
        -- a boolean there would throw on the field read, and the throw would
        -- escape with the mute flag up -- silencing every live whisper sound,
        -- keyword sound, tab flash and reply-target write until reload.
        --
        -- This spec exists because that guard is invisible to every other
        -- replay test: they all install a real frame, so removing the type
        -- checks breaks nothing they assert.
        local CH, KE = L.loadChatHistory()
        KE.ChatMessageHandler = fakeHandler()
        _G.ChatFrame1 = 42
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")

        CH:DisplayChatHistory()

        assert.equals(0, #KE.ChatMessageHandler.calls)
        assert.is_false(KE.ChatMessageHandler.replaying)
    end)

    it("arms exactly one replay per session, not one per enable", function()
        -- A recording timer, so the assertion is about how many passes were
        -- ARMED. Observing the latch flag alone would pass an implementation
        -- that sets it and schedules twice anyway.
        local armed = {}
        local CH, KE = L.loadChatHistory({
            C_Timer = { After = function(_, fn) armed[#armed + 1] = fn end },
        })
        KE.ChatMessageHandler = fakeHandler()
        withFrame({ "SAY" })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")

        CH:ScheduleReplay()
        CH:ScheduleReplay()
        assert.equals(1, #armed)

        armed[1]()
        assert.equals(1, #KE.ChatMessageHandler.calls)
    end)

    it("does nothing while the module is off", function()
        local CH, KE = L.loadChatHistory()
        KE.ChatMessageHandler = fakeHandler()
        withFrame({ "SAY" })
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        KE.db.profile.Skinning.ChatHistory.Enabled = false
        CH:DisplayChatHistory()

        assert.equals(0, #KE.ChatMessageHandler.calls)
    end)
end)

describe("ChatHistory persistence predicate", function()
    it("is true only when everything lines up", function()
        local CH = L.loadChatHistory()
        assert.is_true(CH:IsPersistenceActive())
    end)

    it("is false while the module itself is disabled", function()
        local CH = L.loadChatHistory()
        CH.IsEnabled = function() return false end
        assert.is_false(CH:IsPersistenceActive())
    end)

    it("is false while the chat skin is off", function()
        local CH = L.loadChatHistory()
        CH.ChatSkinActive = function() return false end
        assert.is_false(CH:IsPersistenceActive())
    end)

    it("is false while the db switch is off", function()
        local CH, KE = L.loadChatHistory()
        KE.db.profile.Skinning.ChatHistory.Enabled = false
        assert.is_false(CH:IsPersistenceActive())
    end)

    it("is false inside an instance", function()
        local CH = L.loadChatHistory({ IsInInstance = inInstance() })
        assert.is_false(CH:IsPersistenceActive())
    end)

    it("is false when the instance query cannot be read", function()
        local CH = L.loadChatHistory({ IsInInstance = function() error("boom") end })
        assert.is_false(CH:IsPersistenceActive())
    end)
end)

describe("ChatHistory typed-line store", function()
    it("stores a typed line", function()
        local CH, KE = L.loadChatHistory()
        assert.is_true(CH:RecordTypedLine("/say hello"))
        assert.equals("/say hello", KE.db.char.ChatTypingHistory[1])
    end)

    it("refuses secret text", function()
        local CH, KE = L.loadChatHistory({ issecretvalue = secretIs("/say hello") })
        assert.is_false(CH:RecordTypedLine("/say hello"))
        assert.equals(0, #KE.db.char.ChatTypingHistory)
    end)

    it("refuses an empty or non-string line", function()
        local CH, KE = L.loadChatHistory()
        assert.is_false(CH:RecordTypedLine(""))
        assert.is_false(CH:RecordTypedLine(nil))
        assert.is_false(CH:RecordTypedLine(42))
        assert.equals(0, #KE.db.char.ChatTypingHistory)
    end)

    it("refuses everything typed inside an instance", function()
        local CH, KE = L.loadChatHistory({ IsInInstance = inInstance() })
        assert.is_false(CH:RecordTypedLine("/say hello"))
        assert.equals(0, #KE.db.char.ChatTypingHistory)
    end)

    it("refuses while the chat skin is off", function()
        local CH, KE = L.loadChatHistory()
        CH.ChatSkinActive = function() return false end
        assert.is_false(CH:RecordTypedLine("/say hello"))
        assert.equals(0, #KE.db.char.ChatTypingHistory)
    end)

    it("caps the saved list at fifty, dropping the oldest", function()
        local CH, KE = L.loadChatHistory()
        for i = 1, 55 do CH:RecordTypedLine("line " .. i) end
        local saved = KE.db.char.ChatTypingHistory
        assert.equals(50, #saved)
        assert.equals("line 6", saved[1])
        assert.equals("line 55", saved[50])
    end)
end)

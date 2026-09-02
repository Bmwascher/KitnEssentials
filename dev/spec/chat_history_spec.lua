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

    it("refuses when the instance check throws, returns nil, or returns a secret", function()
        local flag = {}
        local variants = {
            { IsInInstance = function() error("boom") end },
            { IsInInstance = function() return nil end },
            { IsInInstance = function() return flag, "none" end, issecretvalue = secretIs(flag) },
        }
        for _, overrides in ipairs(variants) do
            local CH, KE = L.loadChatHistory(overrides)
            CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
            assert.equals(0, #KE.db.char.ChatHistory)
        end
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

    it("refuses a row whose timestamp reads secret at capture time, or when neither clock is installed", function()
        -- The timestamp goes to disk like any other field, so it is refused at
        -- CAPTURE. RowIsReplayable checks it again on the way back out, but a
        -- check on read cannot unwrite a value that was already persisted.
        local stamp = {}
        local variants = {
            { GetServerTime = function() return stamp end, issecretvalue = secretIs(stamp) },
            { GetServerTime = false, time = false },
        }
        for _, overrides in ipairs(variants) do
            local CH, KE = L.loadChatHistory(overrides)
            CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
            assert.equals(0, #KE.db.char.ChatHistory)
        end
    end)

    it("falls back to time() when the server clock returns no number or is not installed", function()
        local variants = {
            { GetServerTime = function() return nil end },
            { GetServerTime = false },
        }
        for _, overrides in ipairs(variants) do
            local CH, KE = L.loadChatHistory(overrides)
            CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
            assert.equals(1000, KE.db.char.ChatHistory[1].time)
        end
    end)

    it("refuses when the fallback clock reads secret or returns no usable number", function()
        local stamp = {}
        local variants = {
            { GetServerTime = function() return nil end, time = function() return stamp end, issecretvalue = secretIs(stamp) },
            { GetServerTime = function() return nil end, time = function() return "nownow" end },
        }
        for _, overrides in ipairs(variants) do
            local CH, KE = L.loadChatHistory(overrides)
            CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
            assert.equals(0, #KE.db.char.ChatHistory)
        end
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

    it("trims to the cap, dropping the oldest, and keeps exactly the number the cap advertises", function()
        local variants = {
            { size = 3, count = 5, first = "m3", last = "m5" },
            { size = 4, count = 4, first = "m1", last = "m4" },
        }
        for _, v in ipairs(variants) do
            local CH, KE = L.loadChatHistory()
            KE.db.profile.Skinning.ChatHistory.Size = v.size
            for i = 1, v.count do CH:SaveChatHistory("CHAT_MSG_SAY", "m" .. i, "Bob") end
            local data = KE.db.char.ChatHistory
            assert.equals(v.size, #data)
            assert.equals(v.first, data[1][1])
            assert.equals(v.last, data[v.size][1])
        end
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

    it("drops the old profile's registrations when settings change under it", function()
        -- ProfileManager refreshes db and flips enable state only on a
        -- mismatch, calling ApplySettings on everything else. Without the
        -- unregister a profile that switches a type OFF keeps paying dispatch
        -- for it, and one that switches a type ON never captures it until a
        -- reload. The existing registration spec calls RegisterHistoryEvents
        -- directly, so it cannot see either.
        local CH, KE = L.loadChatHistory()
        local registered, cleared = {}, 0
        CH.RegisterEvent = function(_, event) registered[event] = true end
        CH.UnregisterAllEvents = function() cleared = cleared + 1; registered = {} end

        KE.db.profile.Skinning.ChatHistory.ShowTypes.SAY = false
        CH:ApplySettings()
        assert.equals(1, cleared)
        assert.is_nil(registered.CHAT_MSG_SAY)

        KE.db.profile.Skinning.ChatHistory.ShowTypes.SAY = true
        CH:ApplySettings()
        assert.equals(2, cleared)
        assert.is_true(registered.CHAT_MSG_SAY)
    end)

    it("registers nothing at all once the feature is switched off", function()
        local CH, KE = L.loadChatHistory()
        local registered, cleared = {}, 0
        CH.RegisterEvent = function(_, event) registered[event] = true end
        CH.UnregisterAllEvents = function() cleared = cleared + 1; registered = {} end

        KE.db.profile.Skinning.ChatHistory.Enabled = false
        CH:ApplySettings()
        assert.equals(1, cleared)
        assert.is_nil(next(registered))
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

    it("refuses a row whose stored body, sender, or timestamp reads secret at replay time", function()
        local stamp = {}
        local variants = {
            { issecretvalue = secretIs("hello"), row = { "hello", "Bob", event = "CHAT_MSG_SAY", time = 5 } },
            { issecretvalue = secretIs("Bob"), row = { "hello", "Bob", event = "CHAT_MSG_SAY", time = 5 } },
            { issecretvalue = secretIs(stamp), row = { "hello", "Bob", event = "CHAT_MSG_SAY", time = stamp } },
        }
        for _, v in ipairs(variants) do
            local CH, KE = L.loadChatHistory({ issecretvalue = v.issecretvalue })
            KE.db.char.ChatHistory[1] = v.row
            assert.is_false(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
        end
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

    it("stays unmuted when a dispatch reconfigures a frame it has not reached", function()
        -- Replay runs third-party message filters, so an addon reacting to a
        -- replayed line can rewrite another chat frame's messageTypeList while
        -- the pass is still walking the frames. Before the snapshot, the pass
        -- read that list live and iterated it inside the mute window, so the
        -- throw escaped with every live whisper sound, keyword sound, tab
        -- flash and reply-target write silenced until reload.
        --
        -- Nothing else in this file can see the regression: every other replay
        -- spec leaves the frame list alone from first dispatch to last.
        local CH, KE, _, caught = L.loadChatHistory()
        _G.ChatFrame1 = { messageTypeList = { "SAY" } }
        _G.ChatFrame2 = { messageTypeList = { "SAY" } }
        _G.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }

        KE.ChatMessageHandler = {
            replaying = false,
            ChatFrame_MessageEventHandler = function(_, frame)
                if frame == _G.ChatFrame1 then
                    -- What a filter reconfiguring a chat frame looks like from
                    -- here: the list stops being a table mid-pass.
                    _G.ChatFrame2.messageTypeList = 7
                end
            end,
        }

        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")
        CH:DisplayChatHistory()

        -- The pass survives it, because the types it compares were copied
        -- before the flag went up ...
        assert.is_false(KE.ChatMessageHandler.replaying)
        -- ... and nothing was swallowed on the way through.
        assert.equals(0, #caught)
    end)

    it("stays unmuted when a row throws while the dispatch arguments are read", function()
        -- Lua evaluates arguments before pcall takes over, so the seventeen
        -- reads that build a dispatch happen inside the mute window and outside
        -- the per-dispatch pcall. Rows are references into saved variables, so a
        -- row that behaves differently after the prepass has cleared it puts a
        -- throw exactly there -- reachable only by the OUTER pcall.
        --
        -- The metatable arms after the prepass rather than before, because the
        -- prepass reads every slot too; arming early would throw there instead,
        -- outside the window, and prove nothing about the flag.
        local CH, KE, _, caught = L.loadChatHistory()
        withFrame({ "SAY" })
        KE.ChatMessageHandler = {
            replaying = false,
            ChatFrame_MessageEventHandler = function() end,
        }
        CH:SaveChatHistory("CHAT_MSG_SAY", "hello", "Bob")

        local armed = false
        setmetatable(KE.db.char.ChatHistory[1], {
            __index = function(_, key)
                if armed and type(key) == "number" then error("boom") end
                return nil
            end,
        })

        local realRow = CH.RowIsReplayable
        CH.RowIsReplayable = function(self, row)
            local ok = realRow(self, row)
            armed = true
            return ok
        end

        CH:DisplayChatHistory()

        -- Live chat is not left muted ...
        assert.is_false(KE.ChatMessageHandler.replaying)
        -- ... and the structural failure was surfaced, not swallowed.
        assert.equals(1, #caught)
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

describe("ChatHistory Battle.net sender token", function()
    local function fakeHandler()
        local calls = {}
        return {
            replaying = false,
            calls = calls,
            ChatFrame_MessageEventHandler = function(self, frame, event, ...)
                calls[#calls + 1] = { frame = frame, event = event, args = { ... } }
            end,
        }
    end

    local function withFrame(messageTypes)
        _G.ChatFrame1 = { messageTypeList = messageTypes }
        return _G.ChatFrame1
    end

    -- CHAT_MSG_BN_WHISPER's payload: text(1), the token(2), ..., lineID(11),
    -- guid(12), bnSenderID(13).
    local function saveBNWhisper(CH, token, senderID)
        CH:SaveChatHistory("CHAT_MSG_BN_WHISPER", "hello", token,
            nil, nil, nil, nil, nil, nil, nil, nil, 11, nil, senderID)
    end

    describe("store", function()
        it("resolves a tokenized sender to the full BattleTag, overwriting row[2] entirely", function()
            -- accountName is deliberately a different, token-shaped value: if
            -- the code stored it instead of battleTag, this assertion catches
            -- it rather than passing by coincidence.
            local CH, KE = L.loadChatHistory({
                C_BattleNet = {
                    GetAccountInfoByID = function(id)
                        if id == 5 then return { battleTag = "SoTilted#1527", accountName = "|Kf9|k" } end
                    end,
                },
            })
            saveBNWhisper(CH, "|Kf1|k", 5)
            local row = KE.db.char.ChatHistory[1]
            assert.equals("SoTilted#1527", row.bnTag)
            assert.equals("SoTilted#1527", row[2])
        end)

        it("refuses the row when the lookup does not resolve", function()
            local CH, KE = L.loadChatHistory()
            saveBNWhisper(CH, "|Kf1|k", 5)
            assert.equals(0, #KE.db.char.ChatHistory)
        end)

        it("refuses the row when the resolved BattleTag is empty", function()
            local CH, KE = L.loadChatHistory({
                C_BattleNet = { GetAccountInfoByID = function() return { battleTag = "" } end },
            })
            saveBNWhisper(CH, "|Kf1|k", 5)
            assert.equals(0, #KE.db.char.ChatHistory)
        end)

        it("refuses the row when argument 13 is not a positive number", function()
            -- The lookup resolves for any id, so the range test is the only
            -- thing that can refuse this row. With the loader default, which
            -- returns nil, the empty-tag guard would refuse it instead and the
            -- case would pass without the range test mattering.
            local CH, KE = L.loadChatHistory({
                C_BattleNet = {
                    GetAccountInfoByID = function() return { battleTag = "SoTilted#1527" } end,
                },
            })
            saveBNWhisper(CH, "|Kf1|k", 0)
            assert.equals(0, #KE.db.char.ChatHistory)
        end)

        it("leaves an ordinary sender name alone", function()
            local CH, KE = L.loadChatHistory()
            CH:SaveChatHistory("CHAT_MSG_GUILD", "hello", "Bob")
            assert.is_nil(KE.db.char.ChatHistory[1].bnTag)
            assert.equals("Bob", KE.db.char.ChatHistory[1][2])
        end)

        -- The sender id is refused by the coercion loop's secrecy check, which
        -- runs over every argument, rather than by a test of its own. Asserted
        -- here because the branch below compares it, and a comparison against a
        -- secret throws.
        it("refuses the row when argument 13 reads secret", function()
            -- A secret NUMBER, not a table. A table would be refused by the
            -- type check further down and the case would pass without the
            -- secrecy check ever mattering.
            local CH, KE = L.loadChatHistory({
                issecretvalue = secretIs(7),
                C_BattleNet = {
                    GetAccountInfoByID = function() return { battleTag = "SoTilted#1527" } end,
                },
            })
            saveBNWhisper(CH, "|Kf1|k", 7)
            assert.equals(0, #KE.db.char.ChatHistory)
        end)

        -- The lookup's own return is checked separately from its arguments: a
        -- clean id can still hand back a secret tag, and storing that would put
        -- a value on disk that throws on every later read.
        it("refuses the row when the looked-up BattleTag reads secret", function()
            -- A secret STRING, for the same reason: a table would be caught by
            -- the type check and prove nothing about the secrecy check.
            local CH, KE = L.loadChatHistory({
                issecretvalue = secretIs("SoTilted#1527"),
                C_BattleNet = {
                    GetAccountInfoByID = function() return { battleTag = "SoTilted#1527" } end,
                },
            })
            saveBNWhisper(CH, "|Kf1|k", 5)
            assert.equals(0, #KE.db.char.ChatHistory)
        end)

        it("refuses the row when the looked-up BattleTag is not a string", function()
            for _, bad in ipairs({ false, true, 5, {} }) do
                local CH, KE = L.loadChatHistory({
                    C_BattleNet = { GetAccountInfoByID = function() return { battleTag = bad } end },
                })
                saveBNWhisper(CH, "|Kf1|k", 5)
                assert.equals(0, #KE.db.char.ChatHistory)
            end
        end)
    end)

    describe("RowIsReplayable", function()
        it("refuses a legacy row that still carries the token in row[2]", function()
            local CH, KE = L.loadChatHistory()
            KE.db.char.ChatHistory[1] = { "hello", "|Kf1|k", event = "CHAT_MSG_BN_WHISPER", time = 5 }
            assert.is_false(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
        end)

        it("refuses a row whose stored BattleTag reads secret", function()
            -- A secret STRING, and not the one in row[2]. A table would be
            -- refused by the type check one line below the secrecy check, and
            -- a value shared with row[2] by the argument loop.
            local CH, KE = L.loadChatHistory({ issecretvalue = secretIs("Other#1") })
            KE.db.char.ChatHistory[1] =
                { "hello", "SoTilted#1527", event = "CHAT_MSG_BN_WHISPER", time = 5, bnTag = "Other#1" }
            assert.is_false(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
        end)

        -- The prepass runs outside every pcall, so a row that reaches
        -- strmatch with a non-string tag takes the whole replay down.
        it("refuses a row whose stored BattleTag is not a string", function()
            local CH, KE = L.loadChatHistory()
            for _, bad in ipairs({ false, true, 5, {} }) do
                KE.db.char.ChatHistory[1] =
                    { "hello", "SoTilted#1527", event = "CHAT_MSG_BN_WHISPER", time = 5, bnTag = bad }
                assert.is_false(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
            end
        end)

        it("accepts a resolved Battle.net row", function()
            local CH, KE = L.loadChatHistory()
            KE.db.char.ChatHistory[1] =
                { "hello", "SoTilted#1527", event = "CHAT_MSG_BN_WHISPER", time = 5, bnTag = "SoTilted#1527" }
            assert.is_true(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
        end)

        it("still accepts an ordinary guild row", function()
            local CH, KE = L.loadChatHistory()
            KE.db.char.ChatHistory[1] = { "hello", "Bob", event = "CHAT_MSG_GUILD", time = 5 }
            assert.is_true(CH:RowIsReplayable(KE.db.char.ChatHistory[1]))
        end)
    end)

    describe("replay resolve", function()
        it("substitutes the matching friend's current name and id", function()
            local CH, KE = L.loadChatHistory({
                BNGetNumFriends = function() return 1 end,
                C_BattleNet = {
                    GetFriendAccountInfo = function(i)
                        if i == 1 then
                            return { battleTag = "SoTilted#1527", accountName = "Brandon Burnside", bnetAccountID = 10 }
                        end
                    end,
                },
            })
            KE.ChatMessageHandler = fakeHandler()
            withFrame({ "BN_WHISPER" })
            KE.db.char.ChatHistory[1] =
                { "hello", "SoTilted#1527", event = "CHAT_MSG_BN_WHISPER", time = 5, bnTag = "SoTilted#1527" }
            CH:DisplayChatHistory()

            assert.equals(1, #KE.ChatMessageHandler.calls)
            local args = KE.ChatMessageHandler.calls[1].args
            assert.equals("Brandon Burnside", args[2])
            assert.equals(10, args[13])
        end)

        it("falls back to the truncated tag and no id when no friend matches", function()
            local CH, KE = L.loadChatHistory({ BNGetNumFriends = function() return 0 end })
            KE.ChatMessageHandler = fakeHandler()
            withFrame({ "BN_WHISPER" })
            KE.db.char.ChatHistory[1] =
                { "hello", "SoTilted#1527", event = "CHAT_MSG_BN_WHISPER", time = 5, bnTag = "SoTilted#1527" }
            CH:DisplayChatHistory()

            assert.equals(1, #KE.ChatMessageHandler.calls)
            local args = KE.ChatMessageHandler.calls[1].args
            assert.equals("SoTilted", args[2])
            assert.is_nil(args[13])
        end)

        it("passes a plain row's arguments through unresolved", function()
            local CH, KE = L.loadChatHistory()
            KE.ChatMessageHandler = fakeHandler()
            withFrame({ "GUILD" })
            CH:SaveChatHistory("CHAT_MSG_GUILD", "hello", "Bob")
            CH:DisplayChatHistory()

            assert.equals(1, #KE.ChatMessageHandler.calls)
            assert.equals("Bob", KE.ChatMessageHandler.calls[1].args[2])
        end)

        it("never dispatches a legacy row still carrying the token, and never throws", function()
            local CH, KE, _, caught = L.loadChatHistory()
            KE.ChatMessageHandler = fakeHandler()
            withFrame({ "BN_WHISPER" })
            KE.db.char.ChatHistory[1] = { "hello", "|Kf1|k", event = "CHAT_MSG_BN_WHISPER", time = 5 }
            CH:DisplayChatHistory()

            assert.equals(0, #KE.ChatMessageHandler.calls)
            assert.equals(0, #caught)
        end)
    end)
end)

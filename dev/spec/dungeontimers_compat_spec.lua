-- Adapter behaviors: stop/expiry policy, reveal/retire jobs across holds,
-- synthetic children, message lead, shield watch, lifecycle boundaries, span
-- normalization, explicit admission, timeline anchoring and holds, the
-- cast-start confirm and observation window, and refused-enable teardown.
-- The ScheduleTimer/CancelTimer sink records jobs so a case can fire a
-- callback as AceTimer would. Stub frames track their own shown flag because
-- the layout stack counts only shown bars, and that gate reads the frame
-- rather than any value a pure predicate could take. Every other stub only
-- records calls or returns a fixed value. Provider setup uses mutable profile
-- inputs and queued callbacks to check prompt ownership and acceptance re-reads,
-- which its pure planner cannot establish. Aura retry cases use the real
-- registry with recorded native calls and deferred callbacks to check
-- adapter teardown; they do not establish client restrictions or playback.
local loader = require("dev.spec._ke_loader")

-- The default mock frame's catch-all __index resolves every missing key to a
-- function, so CreateBar's `frame.icon:SetTexture(...)` fails against it.
local FRAME_METHODS = {
    "Show", "Hide", "SetShown", "SetSize", "SetPoint", "SetAllPoints",
    "ClearAllPoints", "SetScript", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetMinMaxValues", "SetValue",
    "SetStatusBarTexture", "SetStatusBarColor", "SetFont", "SetText", "SetFormattedText",
    "SetTextColor", "SetJustifyH", "SetAlpha", "SetTexture",
}
local function newPlainStubFrame()
    local f = { _scripts = {}, _shown = true }
    for _, m in ipairs(FRAME_METHODS) do f[m] = function() end end
    f.Show = function(self) self._shown = true end
    f.Hide = function(self) self._shown = false end
    f.IsShown = function(self) return self._shown end
    f.CreateFontString = function() return newPlainStubFrame() end
    f.CreateTexture = function() return newPlainStubFrame() end
    f.GetMinMaxValues = function() return 0, 0 end
    f.SetScript = function(self, key, fn) self._scripts[key] = fn end
    f.GetScript = function(self, key) return self._scripts[key] end
    return f
end

describe("DungeonTimers compatibility", function()
    local DT, KE, State, scheduled, now, soundCalls

    -- Presentations are keyed by private table identity, so membership is
    -- tested by frame identity rather than by a predictable key.
    local function barsContains(frame)
        for _, f in pairs(DT.bars) do
            if f == frame then return true end
        end
        return false
    end

    -- Synthetic presentations have no lookup registry beyond DT.bars and
    -- their own record, so a case matches on the record shape.
    local function findSynthetic(kind, filterFn)
        local matches = {}
        for _, frame in pairs(DT.bars) do
            local record = frame._dtPresentation
            if record and record.synthetic == kind and (not filterFn or filterFn(record)) then
                matches[#matches + 1] = { frame = frame, record = record }
            end
        end
        return matches
    end

    -- The primary is not keyed by its published label, so it is reached
    -- through the instance store and the presentation registry.
    local function findPrimaryFrame(owner, label)
        local inst = State.Find(DT._state, owner, label)
        local presentations = inst and DT._presentations[inst]
        return presentations and presentations.primary
    end

    -- The module captures its timeline constants and issecretvalue at load,
    -- so the hold/confirm cases load their own instance with the timeline
    -- Enum and a guard stub that treats { __secret = true } and the
    -- boss-shaped string "boss9" as secret (the string is what makes the
    -- secret guard's absence observable). The stub proves KE's guards are
    -- present only; native secrecy of the unit token and of GetEventState's return
    -- is a client observation (BugSack). opts.timelineEnum = false loads
    -- without the state enum for the no-enum refusal. Reveal jobs are fired
    -- by hand from the recorded sink, never by time.
    local function loadTimelineModule(opts)
        local clock = { now = 0 }
        local timers = {}
        local events = { registered = {}, unregistered = {} }
        function events.count(list, name)
            local n = 0
            for _, e in ipairs(list) do if e == name then n = n + 1 end end
            return n
        end
        -- `x and nil or y` always yields y, so the enum choice is explicit.
        local timelineStates = { Active = 0, Paused = 1, Finished = 2, Canceled = 3 }
        if opts and opts.timelineEnum == false then timelineStates = nil end
        local DT2, KE2 = loader.loadDungeonTimers({ withEncounterData = false }, {
            CreateFrame = function() return newPlainStubFrame() end,
            GetTime = function() return clock.now end,
            issecretvalue = function(v)
                return (type(v) == "table" and v.__secret == true) or v == "boss9"
            end,
            Enum = {
                UnitAuraSoundTrigger = { Added = "Added" },
                EncounterTimelineEventSource = { Encounter = 0 },
                EncounterTimelineEventState = timelineStates,
            },
        })
        KE2.ApplyFramePosition = function() end
        DT2.ScheduleTimer = function(_, fn, delay, arg)
            local h = { fn = fn, delay = delay, arg = arg, canceled = false }
            timers[#timers + 1] = h
            return h
        end
        DT2.CancelTimer = function(_, h) if h then h.canceled = true end end
        DT2.RegisterEvent = function(_, event) events.registered[#events.registered + 1] = event end
        DT2.UnregisterEvent = function(_, event) events.unregistered[#events.unregistered + 1] = event end
        DT2.RegisterMessage = function() end
        DT2.UnregisterMessage = function() end

        local function contract(extra)
            local c = {
                kind = "Timer", isCooldown = true, policy = "estimated-impact",
                spanMode = "remaining-only", stopTolerance = 0.15,
                collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished",
            }
            for k, v in pairs(extra or {}) do c[k] = v end
            return c
        end
        KE2.EncounterData = {
            [2] = {
                name = "Explicit Boss", dungeon = "Explicit Dungeon", timerPolicy = "explicit",
                spells = {
                    -- Slam-shaped: opts into the confirm; showAtSeconds 1
                    -- floors to 4.15, so the reveal and retire are jobs.
                    [700] = { name = "Confirm Row", castType = "begincast", castDuration = 4,
                              showAtSeconds = 1, sound = "Alert",
                              timerSource = contract({ castConfirm = "boss-cast-start" }) },
                    -- Bellow-shaped: anchor only, always visible, no jobs.
                    [701] = { name = "Anchor Row", castType = "begincast", castDuration = 3,
                              showAtSeconds = 0, sound = "Alert", timerSource = contract() },
                    -- A shield parent, so ENCOUNTER_START registers the shield
                    -- feature's events; no case here publishes it.
                    [702] = { name = "Shield Parent", castType = "cast", castDuration = 0,
                              timerSource = contract() },
                },
                shields = { { parent = 702, baseAmount = 100, timeout = 20 } },
            },
        }
        KE2.LSM = { Fetch = function() return "path/Alert.ogg" end }
        if opts and opts.encounterData then opts.encounterData(KE2.EncounterData, contract) end
        KE2.db = {
            profile = {
                DungeonTimers = {
                    Enabled = true, RoleFilterEnabled = false, MutePresetSounds = false,
                    BarGroup = {}, TextGroup = {},
                },
            },
        }
        DT2:OnEnable()
        local State2 = KE2._DungeonTimerState
        local owner = { GetEncounterID = function() return 2 end }
        DT2:OnEncounterStart(nil, 2)

        local function find(label)
            local inst = State2.Find(DT2._state, owner, label)
            local presentations = inst and DT2._presentations[inst]
            return inst, presentations and presentations.primary
        end
        -- Receipt plus the correlated ADDED on the same tick with the
        -- receipt's own duration, as the publisher's dispatch delivers them.
        local function publish(spellId, label, remaining, eventId, maxQueue)
            DT2:EventCallback("BigWigs_Timer", owner, spellId, remaining, nil, label, nil, nil, true, true)
            if eventId then
                DT2:OnEncounterTimelineEventAdded(nil, { source = 0, id = eventId, duration = remaining, maxQueueDuration = maxQueue })
            end
            return find(label)
        end
        local function tick(frame) frame:GetScript("OnUpdate")(frame, 0) end
        local function findJob(kind, inst)
            for job in pairs(DT2._jobs) do
                if job.kind == kind and job.instance == inst then return job end
            end
            return nil
        end
        return {
            DT = DT2, KE = KE2, State = State2, clock = clock, timers = timers, events = events,
            owner = owner, publish = publish, find = find, tick = tick, findJob = findJob,
        }
    end

    before_each(function()
        now = 0

        -- The spy must be assigned to _G BEFORE loadDungeonTimers runs: the
        -- module captures PlaySoundFile as a file-local upvalue at load.
        soundCalls = {}
        _G.PlaySoundFile = function(file) soundCalls[#soundCalls + 1] = file end
        _G.UnitGetTotalAbsorbs = function() return nil end

        DT, KE = loader.loadDungeonTimers({ withEncounterData = false }, {
            CreateFrame = function() return newPlainStubFrame() end,
            GetTime = function() return now end,
        })

        -- OnEnable reaches KE:ApplyFramePosition, which the loader's KE seed lacks.
        KE.ApplyFramePosition = function() end

        scheduled = {}
        DT.ScheduleTimer = function(_, fn, delay, arg)
            local h = { fn = fn, delay = delay, arg = arg, canceled = false }
            scheduled[#scheduled + 1] = h
            return h
        end
        DT.CancelTimer = function(_, h)
            if h then h.canceled = true end
        end
        DT.RegisterEvent = function() end
        DT.UnregisterEvent = function() end
        DT.RegisterMessage = function() end
        DT.UnregisterMessage = function() end

        State = KE._DungeonTimerState

        local function explicitContract()
            return {
                kind = "Timer", isCooldown = true, policy = "estimated-impact",
                spanMode = "remaining-only", stopTolerance = 0.15,
                collisionPolicy = "refuse-unresolved-label",
            }
        end

        KE.EncounterData = {
            [1] = {
                name = "Compat Boss",
                dungeon = "Compat Dungeon",
                spells = {
                    [100] = { name = "Countdown", castType = "cast", castDuration = 10, showAtSeconds = 5 },
                    [200] = { name = "Phantom Parent", castType = "cast", castDuration = 10 },
                    [201] = { name = "Phantom Child", phantomFollowupOf = 200, duration = 6 },
                    [300] = { name = "Postcast Parent", castType = "cast", postCastBar = { duration = 8 } },
                    [400] = { name = "Message Lead", spawnOnMessage = true, duration = 5, leadDelay = 4 },
                    [500] = { name = "Shield Stop", castType = "channel", channelDuration = 20,
                               shieldBar = { baseAmount = 100 } },
                    [501] = { name = "Shield Expiry", castType = "channel", channelDuration = 20,
                               shieldBar = { baseAmount = 50 } },
                },
            },
            -- Synthetic S2-style pilot encounter: two explicit estimated-
            -- impact Timer rows sharing the collision policy, so a
            -- cross-key label collision can be exercised without touching
            -- the production EncounterData.
            [2] = {
                name = "Explicit Boss",
                dungeon = "Explicit Dungeon",
                timerPolicy = "explicit",
                spells = {
                    [700] = { name = "Estimated Cast", castType = "begincast", castDuration = 3,
                              showAtSeconds = 1, sound = "Alert", timerSource = explicitContract() },
                    [701] = { name = "Estimated Cast Other Key", castType = "begincast", castDuration = 3,
                              showAtSeconds = 1, sound = "Alert", timerSource = explicitContract() },
                    -- Zero curation: the cue ends with the provider deadline.
                    [703] = { name = "Provider Deadline", castType = "begincast", castDuration = 0,
                              showAtSeconds = 5, sound = "Alert", timerSource = explicitContract() },
                },
            },
        }
        KE.LSM = { Fetch = function() return "path/Alert.ogg" end }

        KE.EncounterData[3] = {
            name = "Cue Boss", dungeon = "Cue Dungeon", timerPolicy = "explicit",
            spells = {
                [800] = { name = "Cooldown Row", castType = "begincast", castDuration = 0,
                          showAtSeconds = 0, timerSource = explicitContract() },
            },
            phaseCues = {
                window = { name = "Window", iconOverride = 134400, duration = 20, leadDelay = 2, maxPerPull = 2,
                           prepareText = "SOON", endedText = "ENDED", endedDuration = 2,
                           display = "bar", displayText = "OPEN", showAtSeconds = 0,
                           sound = "Alert", soundOnHide = "Alert",
                           source = { kind = "Message", key = 900 } },
                phase = { name = "Phase", iconOverride = 134400, endedText = "ENDED", endedDuration = 2,
                          display = "bar", displayText = "PHASE", showAtSeconds = 0, sound = "Alert",
                          source = { kind = "Timer", key = 800, isCooldown = false } },
                phase_b = { name = "Phase B", iconOverride = 134400,
                            display = "bar", displayText = "PHASE B", showAtSeconds = 0,
                            source = { kind = "Timer", key = 801, isCooldown = false } },
            },
        }

        KE.db = {
            profile = {
                DungeonTimers = {
                    Enabled = true,
                    RoleFilterEnabled = false,
                    MutePresetSounds = false,
                    BarGroup = {},
                    TextGroup = {},
                },
            },
        }

        DT:OnEnable()
    end)

    it("nonlegacy policies never enter a cast or followup on stop/expiry", function()
        local store = State.New()
        State.AdmitOwner(store, "ownerA", 1)

        for _, policy in ipairs({ "countdown-only", "qualified-active" }) do
            local binding = {
                encounterId = 1, key = 100, kind = "Timer", discriminator = "any",
                policy = policy, spanMode = "remaining-only", curationId = 100, extension = 5,
            }

            local stopLabel = "stop-" .. policy
            local stopInstance = State.Start(store, "ownerA", stopLabel, binding, 10, 10, 0, true)
            assert.equal("retire", State.ClassifyStop(stopInstance, 5, nil))

            local expiryLabel = "expiry-" .. policy
            local expiryInstance = State.Start(store, "ownerA", expiryLabel, binding, 10, 10, 0, true)
            assert.equal("retire", State.ClassifyExpiry(expiryInstance, 10))
            State.Retire(store, expiryInstance)
            assert.is_nil(State.Find(store, "ownerA", expiryLabel))
        end
    end)

    it("legacy stop policy distinguishes early, near-end, stale and in-cast stops, holds effective elapsed, and keeps the forceDuration exception", function()
        local store = State.New()
        State.AdmitOwner(store, "ownerA", 1)
        local binding = {
            encounterId = 1, key = 100, kind = "Timer", discriminator = "any",
            policy = "legacy", spanMode = "remaining-only", curationId = 100, extension = 8,
        }

        local early = State.Start(store, "ownerA", "early", binding, 10, 10, 0, true)
        assert.equal("retire", State.ClassifyStop(early, 2, nil))

        local nearEnd = State.Start(store, "ownerA", "near-end", binding, 10, 10, 0, true)
        assert.equal("enter-legacy-cast", State.ClassifyStop(nearEnd, 9.5, nil))
        assert.equal(8.5, State.BeginLegacyCast(nearEnd, 9.5, 8))

        local stale = State.Start(store, "ownerA", "stale", binding, 10, 10, 0, true)
        assert.equal("retire", State.ClassifyStop(stale, 18.5, nil))

        -- Stop while already in cast always retires, regardless of timing.
        assert.equal("retire", State.ClassifyStop(nearEnd, 100, nil))

        -- A 4-second hold shifts the qualifying instant by exactly 4 seconds
        -- on the wall clock.
        local held = State.Start(store, "ownerA", "held", binding, 10, 10, 0, true)
        State.Pause(store, "ownerA", "held", 3)
        State.Resume(store, "ownerA", "held", 7)
        assert.equal("retire", State.ClassifyStop(held, 9.5, nil))
        assert.equal("enter-legacy-cast", State.ClassifyStop(held, 13.5, nil))

        -- forceDuration 0 and 20 both yield "ignore" (Lua numeric 0 is truthy).
        for _, forceDuration in ipairs({ 0, 20 }) do
            assert.equal("ignore", State.ClassifyStop(held, 999, forceDuration))
        end
    end)

    it("legacy expiry preserves followup timing and consumes eligibility once", function()
        local store = State.New()
        State.AdmitOwner(store, "ownerA", 1)
        local zeroExt = {
            encounterId = 1, key = 100, kind = "Timer", discriminator = "any",
            policy = "legacy", spanMode = "remaining-only", curationId = 100, extension = 0,
        }
        local posExt = {
            encounterId = 1, key = 100, kind = "Timer", discriminator = "any",
            policy = "legacy", spanMode = "remaining-only", curationId = 100, extension = 5,
        }

        local instanceA = State.Start(store, "ownerA", "zero-ext", zeroExt, 10, 10, 0, true)
        assert.equal("legacy-followup-and-retire", State.ClassifyExpiry(instanceA, 10))
        assert.is_true(State.TakeFollowup(store, instanceA))
        assert.is_false(State.TakeFollowup(store, instanceA))
        -- A later Stop does not resurrect the followup once consumed.
        State.ClassifyStop(instanceA, 11, nil)
        assert.is_false(State.TakeFollowup(store, instanceA))

        local instanceB = State.Start(store, "ownerA", "pos-ext", posExt, 10, 10, 0, true)
        assert.equal("keep", State.ClassifyExpiry(instanceB, 10))
        assert.equal("keep", State.ClassifyExpiry(instanceB, 16.4))
        assert.equal("retire", State.ClassifyExpiry(instanceB, 16.5))
        assert.is_nil(instanceB.castClock)

        local instanceC = State.Start(store, "ownerA", "cast-expiry", posExt, 10, 10, 0, true)
        State.BeginLegacyCast(instanceC, 10, 5)
        assert.equal("legacy-followup-and-retire", State.ClassifyExpiry(instanceC, 15))

        local instanceD = State.Start(store, "ownerA", "not-admitted", zeroExt, 10, 10, 0, false)
        assert.equal("legacy-followup-and-retire", State.ClassifyExpiry(instanceD, 10))
        assert.is_false(State.TakeFollowup(store, instanceD))
    end)

    it("hidden presentation reveal/retirement holds across pause, survives inferred cast entry, and the eligibility predicate refuses stale/shown tokens", function()
        local owner = { GetEncounterID = function() return 1 end }
        DT:OnEncounterStart(nil, 1)

        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 100, 10, nil, "Boss Cast", nil, nil, false, true)
        local frame = findPrimaryFrame(owner, "Boss Cast")
        assert.is_not_nil(frame)
        local record = frame._dtPresentation
        assert.is_not_nil(record)

        local revealHandle = record.revealJob and record.revealJob.handle
        assert.is_not_nil(revealHandle)
        assert.equal(15, revealHandle.delay)   -- total(10+10) - showWindow(5)

        -- The countdown displays the S1 total (source remaining plus the
        -- curated extension), not the source clock's own remaining. Only the
        -- integer part is asserted: the fractional suffix depends on the
        -- decimal threshold, which is a different behavior.
        now = 4
        frame:GetScript("OnUpdate")(frame, 0)
        assert.equal("16", frame._lastTimerStr:sub(1, 2))

        -- Pause after four running seconds so the resumed delay can only be
        -- right if the hold preserved the remaining interval.
        DT:EventCallback("BigWigs_PauseBar", owner, "Boss Cast")
        assert.is_true(revealHandle.canceled)

        now = 9
        DT:EventCallback("BigWigs_ResumeBar", owner, "Boss Cast")
        local newRevealHandle = record.revealJob and record.revealJob.handle
        assert.is_not_nil(newRevealHandle)
        assert.equal(11, newRevealHandle.delay)

        -- Fresh instance for the canonical Stop-enters-cast example: receipt
        -- 0, time 10, extension 10, showWindow 5, Stop at 12 leaves reveal
        -- at 15 while the cast ends at 22.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 100, 10, nil, "Boss Cast 2", nil, nil, false, true)
        local frame2 = findPrimaryFrame(owner, "Boss Cast 2")
        local record2 = frame2._dtPresentation
        local revealHandle2 = record2.revealJob and record2.revealJob.handle
        assert.equal(15, revealHandle2.delay)

        now = 12
        DT:EventCallback("BigWigs_StopBar", owner, "Boss Cast 2")
        assert.is_false(revealHandle2.canceled)
        assert.equal(15, revealHandle2.delay)

        -- Stale generation: capture the record, replace the same label, and
        -- confirm the OLD record is no longer current.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 100, 10, nil, "Boss Cast 3", nil, nil, false, true)
        local staleRecord = findPrimaryFrame(owner, "Boss Cast 3")._dtPresentation
        DT:EventCallback("BigWigs_Timer", owner, 100, 10, nil, "Boss Cast 3", nil, nil, false, true)
        assert.is_false(DT._IsPresentationCurrent(staleRecord))

        -- Already-shown: fire the reveal job's callback the way AceTimer
        -- would, then confirm the predicate refuses the now-shown record.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 100, 10, nil, "Boss Cast 4", nil, nil, false, true)
        local shownRecord = findPrimaryFrame(owner, "Boss Cast 4")._dtPresentation
        local shownRevealHandle = shownRecord.revealJob.handle
        shownRevealHandle.fn(shownRevealHandle.arg)
        assert.is_false(DT._IsPresentationCurrent(shownRecord))
    end)

    it("phantom followup survives parent filtering/single stop, replaces on new parent Timer, releases on owner cleanup", function()
        local owner = { GetEncounterID = function() return 1 end }
        DT:OnEncounterStart(nil, 1)

        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 200, 10, nil, "Parent Cast", nil, nil, false, true)
        local matches1 = findSynthetic("phantom", function(r) return r.slotKey == 201 end)
        assert.equal(1, #matches1)
        local phantomFrame1 = matches1[1].frame

        -- A StopBar for the parent leaves the phantom in place.
        DT:EventCallback("BigWigs_StopBar", owner, "Parent Cast")
        assert.is_true(barsContains(phantomFrame1))
        local loneExtent = DT:GetStackExtent("bar")

        -- A parent Timer for a parent disabled through SetSpellDisabled still
        -- spawns/replaces the phantom (independently filtered, immediate),
        -- even though no parent presentation exists for the disabled Timer.
        DT:SetSpellDisabled(200, true)
        DT:EventCallback("BigWigs_Timer", owner, 200, 10, nil, "Parent Cast 2", nil, nil, false, true)
        local matchesDisabled = findSynthetic("phantom", function(r) return r.slotKey == 201 end)
        assert.equal(1, #matchesDisabled)
        local phantomFrameDisabled = matchesDisabled[1].frame
        assert.are_not.equal(phantomFrame1, phantomFrameDisabled)
        assert.is_false(barsContains(phantomFrame1))
        -- Still one live bar-mode phantom, so the published extent must be
        -- the same stride as before the replacement; a stale extent would
        -- still count the released predecessor too.
        assert.equal(loneExtent, DT:GetStackExtent("bar"))
        assert.is_true(matchesDisabled[1].record.generation > matches1[1].record.generation)
        assert.is_nil(findPrimaryFrame(owner, "Parent Cast 2"))
        DT:SetSpellDisabled(200, false)

        -- A second accepted parent Timer replaces the phantom presentation:
        -- one phantom frame, new slot generation.
        DT:EventCallback("BigWigs_Timer", owner, 200, 10, nil, "Parent Cast 3", nil, nil, false, true)
        local matches2 = findSynthetic("phantom", function(r) return r.slotKey == 201 end)
        assert.equal(1, #matches2)
        local phantomFrame2 = matches2[1].frame
        assert.are_not.equal(phantomFrameDisabled, phantomFrame2)
        assert.is_false(barsContains(phantomFrameDisabled))
        assert.is_true(matches2[1].record.generation > matchesDisabled[1].record.generation)

        -- StopBars from the owner releases it.
        DT:EventCallback("BigWigs_StopBars", owner)
        assert.is_false(barsContains(phantomFrame2))
    end)

    it("postcast child outlives parent retirement; owner cleanup and its own replacement still cancel it", function()
        local owner = { GetEncounterID = function() return 1 end }
        DT:OnEncounterStart(nil, 1)

        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 300, 10, nil, "Cast (1)", nil, nil, false, true)
        local primary1 = findPrimaryFrame(owner, "Cast (1)")
        assert.is_not_nil(primary1)
        now = 10
        primary1:GetScript("OnUpdate")(primary1, 0)

        local matches1 = findSynthetic("postcast",
            function(r) return tostring(r.slotKey):find("Cast (1):300", 1, true) ~= nil end)
        assert.equal(1, #matches1)
        local child1 = matches1[1].frame

        -- Retiring the parent instance (already happened via expiry) leaves
        -- the child.
        assert.is_true(barsContains(child1))

        -- Two different counted parent labels retain separate children.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 300, 10, nil, "Cast (2)", nil, nil, false, true)
        local primary2 = findPrimaryFrame(owner, "Cast (2)")
        now = 10
        primary2:GetScript("OnUpdate")(primary2, 0)
        local matches2 = findSynthetic("postcast",
            function(r) return tostring(r.slotKey):find("Cast (2):300", 1, true) ~= nil end)
        assert.equal(1, #matches2)
        local child2 = matches2[1].frame
        assert.are_not.equal(child1, child2)

        -- A second followup for the same parent label replaces its child.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 300, 10, nil, "Cast (1)", nil, nil, false, true)
        local primary1b = findPrimaryFrame(owner, "Cast (1)")
        now = 10
        primary1b:GetScript("OnUpdate")(primary1b, 0)
        local matches1b = findSynthetic("postcast",
            function(r) return tostring(r.slotKey):find("Cast (1):300", 1, true) ~= nil end)
        assert.equal(1, #matches1b)
        local child1b = matches1b[1].frame
        assert.are_not.equal(child1, child1b)
        assert.is_false(barsContains(child1))

        -- child2 expires naturally before owner cleanup runs, leaving an
        -- already-released slot the cleanup pass must not index by a stale key.
        now = 18
        child2:GetScript("OnUpdate")(child2, 0)
        assert.is_false(barsContains(child2))

        -- StopBars from the owner releases the remaining children.
        assert.has_no.errors(function() DT:EventCallback("BigWigs_StopBars", owner) end)
        assert.is_false(barsContains(child1b))
        assert.is_false(barsContains(child2))
        assert.is_nil(DT._slotPresentations[owner])
    end)

    it("message lead job survives unrelated pause, replaces on same-slot Message, cancels on owner cleanup, re-checks admission at fire", function()
        local owner = { GetEncounterID = function() return 1 end }
        local otherOwner = { GetEncounterID = function() return 1 end }
        DT:OnEncounterStart(nil, 1)

        DT:EventCallback("BigWigs_Message", owner, 400, "msg text", nil, nil, false, nil)
        local job1 = DT._slotJobs and DT._slotJobs[owner]
            and DT._slotJobs[owner]["message"] and DT._slotJobs[owner]["message"]["400:400"]
        assert.is_not_nil(job1)
        assert.is_not_nil(job1.handle)
        assert.equal(4, job1.handle.delay)

        -- PauseBar for an unrelated source leaves it scheduled.
        DT:EventCallback("BigWigs_PauseBar", otherOwner, "Some Other Label")
        assert.is_false(job1.handle.canceled)

        -- A second Message for the same slot cancels the first job and
        -- schedules another.
        DT:EventCallback("BigWigs_Message", owner, 400, "msg text 2", nil, nil, false, nil)
        assert.is_true(job1.handle.canceled)
        local job2 = DT._slotJobs[owner]["message"]["400:400"]
        assert.is_not_nil(job2)
        assert.are_not.equal(job1, job2)

        -- StopBars from the owner cancels the pending job.
        DT:EventCallback("BigWigs_StopBars", owner)
        assert.is_true(job2.handle.canceled)

        -- The job fires after the row was disabled: no presentation renders.
        DT:EventCallback("BigWigs_Message", owner, 400, "msg text 3", nil, nil, false, nil)
        local job3 = DT._slotJobs[owner]["message"]["400:400"]
        DT:SetSpellDisabled(400, true)
        local barsBefore = 0
        for _ in pairs(DT.bars) do barsBefore = barsBefore + 1 end
        job3.handle.fn(job3.handle.arg)
        local barsAfter = 0
        for _ in pairs(DT.bars) do barsAfter = barsAfter + 1 end
        assert.equal(barsBefore, barsAfter)

        -- Receipt-time refusal: row 400 is still disabled here, so the
        -- Message must not even schedule a job. Re-enabling afterward has
        -- no pending job to fire, so no cue can appear from that receipt.
        DT:SetSpellDisabled(400, true)
        DT:EventCallback("BigWigs_Message", owner, 400, "msg text 4", nil, nil, false, nil)
        local slotsAfterReceipt = DT._slotJobs[owner] and DT._slotJobs[owner]["message"]
        assert.is_nil(slotsAfterReceipt and slotsAfterReceipt["400:400"])

        DT:SetSpellDisabled(400, false)
        local barsAfterReenable = 0
        for _ in pairs(DT.bars) do barsAfterReenable = barsAfterReenable + 1 end
        assert.equal(barsAfter, barsAfterReenable)
    end)

    it("shield colors use their own defaults and honor live user overrides through reuse and reset", function()
        local owner = { GetEncounterID = function() return 1 end }
        local row = KE.EncounterData[1].spells[500]
        row.color = { 0.8, 0.2, 0.1 }
        row.shieldColor = { 0.2, 0.6, 0.9 }
        DT:OnEncounterStart(nil, 1)
        DT:EventCallback("BigWigs_Timer", owner, 500, 20, nil, "Shield Color", nil, nil, false, true)
        assert.same(row.color, findPrimaryFrame(owner, "Shield Color").barColor)
        DT:_ShowShieldBar(500, "boss1", 42, owner)
        local bar = DT._shieldKits[500]
        assert.same(row.shieldColor, bar.barColor)

        local custom = { 0.7, 0.3, 0.5 }
        DT:SetSpellColorOverride(500, custom)
        DT:ApplySettings()
        assert.same(custom, bar.barColor)
        DT:_HideShieldBar(500)
        DT:_ShowShieldBar(500, "boss1", 43, owner)
        assert.equal(bar, DT._shieldKits[500])
        assert.same(custom, bar.barColor)

        DT:SetSpellColorOverride(500, nil)
        DT:ApplySettings()
        assert.same(row.shieldColor, bar.barColor)
        DT:_ShowShieldBar(501, "boss1", 44, owner)
        assert.same({ 0.137, 0.325, 0.278 }, DT._shieldKits[501].barColor)
    end)

    it("shield pre-channel watch arm/disarm holds on its own clock through pause/stop/expiry and stale-generation guards", function()
        local owner = { GetEncounterID = function() return 1 end }
        DT:OnEncounterStart(nil, 1)

        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 500, 20, nil, "Shield Cast", nil, nil, false, true)
        local watch1 = DT._shieldWatches[500]
        assert.is_not_nil(watch1)
        assert.is_not_nil(watch1.armJob)
        assert.equal(19, watch1.armJob.handle.delay)   -- max(remaining - 1, 0)

        -- Pause cancels the arm job; resume reschedules it with the held remainder.
        DT:EventCallback("BigWigs_PauseBar", owner, "Shield Cast")
        assert.is_true(watch1.armJob.handle.canceled)
        now = 5
        DT:EventCallback("BigWigs_ResumeBar", owner, "Shield Cast")
        local resumedArmHandle = watch1.armJob.handle
        assert.equal(19, resumedArmHandle.delay)

        -- Single Stop leaves the watch and its jobs in place.
        DT:EventCallback("BigWigs_StopBar", owner, "Shield Cast")
        assert.equal(watch1, DT._shieldWatches[500])
        assert.is_false(resumedArmHandle.canceled)

        -- A separate row's zero-extension local expiry also leaves its own
        -- watch in place (the parent presentation retires; the watch does not).
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 501, 20, nil, "Shield Cast Expiry", nil, nil, false, true)
        local watchExpiry = DT._shieldWatches[501]
        assert.is_not_nil(watchExpiry)
        local expiryFrame = findPrimaryFrame(owner, "Shield Cast Expiry")
        assert.is_not_nil(expiryFrame)
        now = 20
        expiryFrame:GetScript("OnUpdate")(expiryFrame, 0)
        assert.equal(watchExpiry, DT._shieldWatches[501])

        -- A second Timer for the same row replaces the watch; the old
        -- watch's jobs are canceled.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 500, 20, nil, "Shield Cast 2", nil, nil, false, true)
        local watch2 = DT._shieldWatches[500]
        assert.is_not_nil(watch2)
        assert.are_not.equal(watch1, watch2)
        assert.is_true(resumedArmHandle.canceled)

        -- StopBars from the owner cancels the watch jobs.
        DT:EventCallback("BigWigs_StopBars", owner)
        assert.is_true(watch2.armJob.handle.canceled)

        -- A stale watch generation fails State.IsSlotCurrent.
        assert.is_false(State.IsSlotCurrent(DT._state, owner, "shieldWatch", 500, watch1.generation))
    end)

    it("same-profile refresh preserves identity; real boundaries retire it; ownerless callbacks cannot trigger a boundary", function()
        local owner = { GetEncounterID = function() return 1 end }
        DT:OnEncounterStart(nil, 1)

        local function freshInstance(text)
            now = 0
            DT:EventCallback("BigWigs_Timer", owner, 100, 10, nil, text, nil, nil, false, true)
            local frame = findPrimaryFrame(owner, text)
            return frame, frame and frame._dtPresentation
        end

        -- StopBars with a nil owner or an owner lacking GetEncounterID is inert.
        local _, recordA = freshInstance("Lifecycle A")
        DT:EventCallback("BigWigs_StopBars", nil)
        DT:EventCallback("BigWigs_StopBars", { notAnOwner = true })
        assert.is_true(State.IsCurrent(DT._state, recordA.instance, recordA.instance.generation,
            recordA.instance.moduleEpoch, recordA.instance.encounterEpoch))

        -- ApplySettings leaves the instance, its generation and scheduled
        -- jobs untouched.
        local existingHandles = {}
        for i = 1, #scheduled do existingHandles[i] = scheduled[i] end
        local generationBefore = recordA.instance.generation
        DT:ApplySettings()
        assert.is_true(State.IsCurrent(DT._state, recordA.instance, generationBefore,
            recordA.instance.moduleEpoch, recordA.instance.encounterEpoch))
        for i = 1, #existingHandles do
            assert.is_false(existingHandles[i].canceled)
        end

        -- OnProfileBoundary retires the instance and cancels its jobs.
        local _, recordB = freshInstance("Lifecycle B")
        local revealHandleB = recordB.revealJob and recordB.revealJob.handle
        DT:OnProfileBoundary()
        assert.is_false(State.IsCurrent(DT._state, recordB.instance, recordB.instance.generation,
            recordB.instance.moduleEpoch, recordB.instance.encounterEpoch))
        if revealHandleB then assert.is_true(revealHandleB.canceled) end

        -- OnEncounterEnd retires the instance for the registered encounter.
        DT:OnEncounterStart(nil, 1)
        local _, recordC = freshInstance("Lifecycle C")
        DT:OnEncounterEnd()
        assert.is_false(State.IsCurrent(DT._state, recordC.instance, recordC.instance.generation,
            recordC.instance.moduleEpoch, recordC.instance.encounterEpoch))

        -- OnDisable retires everything.
        DT:OnEncounterStart(nil, 1)
        local _, recordD = freshInstance("Lifecycle D")
        DT:OnDisable()
        assert.is_false(State.IsCurrent(DT._state, recordD.instance, recordD.instance.generation,
            recordD.instance.moduleEpoch, recordD.instance.encounterEpoch))

        -- A world transition clears an armed watch and prevents a later resume.
        DT:OnEncounterStart(nil, 1)
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 500, 20, nil, "Lifecycle E", nil, nil, false, true)
        local instE = State.Find(DT._state, owner, "Lifecycle E")
        assert.is_not_nil(instE)
        local watchE = DT._shieldWatches[500]
        assert.is_not_nil(watchE)
        local armHandleE = watchE.armJob.handle
        armHandleE.fn(armHandleE.arg)
        assert.is_true(DT._shieldArming[500])

        DT:OnPlayerEnteringWorld()
        assert.is_false(State.IsCurrent(DT._state, instE, instE.generation,
            instE.moduleEpoch, instE.encounterEpoch))
        assert.is_falsy(DT._shieldArming[500])

        local scheduledBefore = #scheduled
        DT:EventCallback("BigWigs_ResumeBar", owner, "Lifecycle E")
        assert.equal(scheduledBefore, #scheduled)

        -- Table-driven: each adapter lifecycle route clears an outstanding
        -- pilot label along with everything else, so a later admission for
        -- the same label is not refused as a duplicate.
        local pilotOwner = { GetEncounterID = function() return 2 end }
        for _, route in ipairs({ "OnProfileBoundary", "OnPlayerEnteringWorld", "OnDisable" }) do
            DT:OnEncounterStart(nil, 2)
            local label = "Route " .. route
            now = 0
            DT:EventCallback("BigWigs_Timer", pilotOwner, 700, 10, nil, label, nil, nil, true, true)
            local firstRouteInst = State.Find(DT._state, pilotOwner, label)
            assert.is_not_nil(firstRouteInst)

            DT:EventCallback("BigWigs_Timer", pilotOwner, 700, 10, nil, label, nil, nil, true, true)
            assert.equal(firstRouteInst, State.Find(DT._state, pilotOwner, label))

            DT[route](DT)
            if route == "OnDisable" then DT:OnEnable() end
            DT:OnEncounterStart(nil, 2)
            DT:EventCallback("BigWigs_Timer", pilotOwner, 700, 10, nil, label, nil, nil, true, true)
            local secondRouteInst = State.Find(DT._state, pilotOwner, label)
            assert.is_not_nil(secondRouteInst)
            assert.are_not.equal(firstRouteInst, secondRouteInst)
        end
    end)

    it("DT._NormalizeSpan branches on spanMode and validates the optional maximum", function()
        local nan = 0 / 0

        local remainingOnlyCases = {
            { hasMax = false }, { max = 5 }, { max = 100 }, { max = "x" }, { max = nan },
        }
        for _, case in ipairs(remainingOnlyCases) do
            local maxTime = case.hasMax == false and nil or case.max
            local a, b = DT._NormalizeSpan("remaining-only", 10, maxTime)
            assert.equal(10, a)
            assert.equal(10, b)
        end

        -- full-span: nil maxTime means span = time.
        local time1, span1 = DT._NormalizeSpan("full-span", 10, nil)
        assert.equal(10, time1)
        assert.equal(10, span1)

        -- full-span: a finite maxTime >= time is accepted as-is.
        local time2, span2 = DT._NormalizeSpan("full-span", 10, 15)
        assert.equal(10, time2)
        assert.equal(15, span2)

        -- full-span refusals: smaller than time, NaN, infinite, a string.
        for _, maxTime in ipairs({ 5, nan, math.huge, "x" }) do
            local refusedTime, reason = DT._NormalizeSpan("full-span", 10, maxTime)
            assert.is_nil(refusedTime)
            assert.equal("string", type(reason))
        end
    end)

    it("explicit Timer adapter admission accepts the exact owned pilot Timer, applies the offset once, and refuses everything else", function()
        local owner = { GetEncounterID = function() return 2 end }
        local wrongEncounterOwner = { GetEncounterID = function() return 1 end }
        DT:OnEncounterStart(nil, 2)

        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Estimated Cast", nil, nil, true, false)
        local frame = findPrimaryFrame(owner, "Estimated Cast")
        assert.is_not_nil(frame)
        local inst = State.Find(DT._state, owner, "Estimated Cast")
        assert.is_not_nil(inst)
        assert.equal("estimated-impact", inst.binding.policy)
        assert.equal(3, inst.binding.extension)

        -- Prove the sound spy is live in the shared fixture: firing the
        -- armed reveal job plays the curated show sound exactly once.
        local record = frame._dtPresentation
        record.revealJob.handle.fn(record.revealJob.handle.arg)
        assert.equal(1, #soundCalls)

        -- The user time offset is applied exactly once, not double-counted
        -- on top of the curated extension already baked into the binding.
        DT:SetSpellTimeOffset(700, 2)
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Estimated Cast Offset", nil, nil, true, true)
        local instOffset = State.Find(DT._state, owner, "Estimated Cast Offset")
        assert.equal(5, instOffset.binding.extension)
        DT:SetSpellTimeOffset(700, 0)

        -- A non-number provider time refuses before conversion, recording no
        -- awaiting-stop entry, so the same label can retry with a valid time.
        DT:EventCallback("BigWigs_Timer", owner, 700, "10", nil, "String Time", nil, nil, true, true)
        assert.is_nil(State.Find(DT._state, owner, "String Time"))
        assert.is_nil(findPrimaryFrame(owner, "String Time"))
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "String Time", nil, nil, true, true)
        assert.is_not_nil(State.Find(DT._state, owner, "String Time"))

        local barsBefore = 0
        for _ in pairs(DT.bars) do barsBefore = barsBefore + 1 end

        -- Wrong discriminator: the provider's isCooldown is false.
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Wrong Discriminator", nil, nil, false, true)
        assert.is_nil(State.Find(DT._state, owner, "Wrong Discriminator"))

        -- Wrong key: no binding exists for this spellId under encounter 2.
        DT:EventCallback("BigWigs_Timer", owner, 702, 10, nil, "Wrong Key", nil, nil, true, true)
        assert.is_nil(State.Find(DT._state, owner, "Wrong Key"))

        -- Wrong owner: this owner's own encounter does not match the
        -- active one.
        DT:EventCallback("BigWigs_Timer", wrongEncounterOwner, 700, 10, nil, "Wrong Owner", nil, nil, true, true)
        assert.is_nil(State.Find(DT._state, wrongEncounterOwner, "Wrong Owner"))

        -- A StartBar only notes evidence and never draws; CastTimer has no
        -- installed binding for this key.
        DT:EventCallback("BigWigs_StartBar", owner, 700, 10, nil, "Start Bar", nil, true, true)
        DT:EventCallback("BigWigs_CastTimer", owner, 700, 10, nil, "Cast Timer")

        local barsAfter = 0
        for _ in pairs(DT.bars) do barsAfter = barsAfter + 1 end
        assert.equal(barsBefore, barsAfter)
    end)

    it("a zero-curation explicit countdown reveals at the configured window, keeps zero extension through presentation and retires at the provider deadline; a positive user offset still extends it", function()
        local owner = { GetEncounterID = function() return 2 end }
        DT:OnEncounterStart(nil, 2)

        -- Source remaining 10, reveal window 5. With zero curation the cue
        -- reveals after 5 and retires at 10; an explicit offset of 2 shifts
        -- both by exactly the offset and nothing else.
        local variants = {
            { name = "zero offset", offset = 0, extension = 0, revealDelay = 5, deadline = 10 },
            { name = "positive offset", offset = 2, extension = 2, revealDelay = 7, deadline = 12 },
        }
        for _, v in ipairs(variants) do
            local label = "Provider Deadline " .. v.name
            DT:SetSpellTimeOffset(703, v.offset)
            local barsBefore = 0
            for _ in pairs(DT.bars) do barsBefore = barsBefore + 1 end

            now = 0
            DT:EventCallback("BigWigs_Timer", owner, 703, 10, nil, label, nil, nil, true, true)
            local frame = findPrimaryFrame(owner, label)
            local inst = State.Find(DT._state, owner, label)
            assert.is_not_nil(frame, v.name)
            assert.is_not_nil(inst, v.name)
            assert.equal("estimated-impact", inst.binding.policy, v.name)
            assert.equal(v.extension, inst.binding.extension, v.name)
            assert.equal(v.extension, frame.extension, v.name)

            local record = frame._dtPresentation
            assert.is_not_nil(record.revealJob, v.name)
            assert.equal(v.revealDelay, record.revealJob.handle.delay, v.name)
            assert.is_false(frame._shown, v.name)
            assert.equal(v.deadline, record.retireJob.handle.delay, v.name)

            now = v.revealDelay
            record.revealJob.handle.fn(record.revealJob.handle.arg)
            assert.is_true(frame._shown, v.name)
            assert.equal(v.extension, frame.extension, v.name)

            now = v.deadline - 0.1
            frame:GetScript("OnUpdate")(frame, 0)
            assert.is_not_nil(State.Find(DT._state, owner, label), v.name)
            assert.is_true(barsContains(frame), v.name)

            now = v.deadline
            frame:GetScript("OnUpdate")(frame, 0)
            assert.is_nil(State.Find(DT._state, owner, label), v.name)
            assert.is_false(barsContains(frame), v.name)
            assert.is_nil(inst.castClock, v.name)

            -- No follow-up presentation of any kind was left behind.
            local barsAfter = 0
            for _ in pairs(DT.bars) do barsAfter = barsAfter + 1 end
            assert.equal(barsBefore, barsAfter, v.name)
        end
        DT:SetSpellTimeOffset(703, 0)
    end)

    it("estimated-impact reveal states keep the frame and forecast intact, and rule 7 suppresses only the deferred reveal's show sound", function()
        -- The spy must be assigned to _G BEFORE loadDungeonTimers runs: the
        -- module captures PlaySoundFile as a file-local upvalue at load.
        -- Own fixture, own spy: distinct from the describe-level soundCalls.
        local revealSoundCalls = {}
        _G.PlaySoundFile = function(file) revealSoundCalls[#revealSoundCalls + 1] = file end

        local localNow = 0
        local DT2, KE2 = loader.loadDungeonTimers({ withEncounterData = false }, {
            CreateFrame = function() return newPlainStubFrame() end,
            GetTime = function() return localNow end,
        })
        KE2.ApplyFramePosition = function() end
        DT2.ScheduleTimer = function(_, fn, delay, arg)
            local h = { fn = fn, delay = delay, arg = arg, canceled = false }
            return h
        end
        DT2.CancelTimer = function(_, h) if h then h.canceled = true end end
        DT2.RegisterEvent = function() end
        DT2.UnregisterEvent = function() end
        DT2.RegisterMessage = function() end
        DT2.UnregisterMessage = function() end
        local State2 = KE2._DungeonTimerState

        local function contract()
            return {
                kind = "Timer", isCooldown = true, policy = "estimated-impact",
                spanMode = "remaining-only", stopTolerance = 0.15,
                collisionPolicy = "refuse-unresolved-label",
            }
        end
        KE2.EncounterData = {
            [2] = {
                name = "Explicit Boss", dungeon = "Explicit Dungeon", timerPolicy = "explicit",
                spells = {
                    -- Lowered window: the floor (extension+tolerance) binds.
                    [700] = { name = "Row A", castType = "begincast", castDuration = 3,
                              showAtSeconds = 1, sound = "Alert", timerSource = contract() },
                    -- Large window: the configured value wins over the floor.
                    [701] = { name = "Row B", castType = "begincast", castDuration = 3,
                              showAtSeconds = 10, sound = "Alert", timerSource = contract() },
                    -- Configured zero: the always-visible exemption.
                    [702] = { name = "Row C", castType = "begincast", castDuration = 3,
                              showAtSeconds = 0, sound = "Alert", timerSource = contract() },
                    -- No curated showAtSeconds at all: inherits the group's
                    -- zero default, same exemption via a different path.
                    [704] = { name = "Row E", castType = "begincast", castDuration = 3,
                              sound = "Alert", timerSource = contract() },
                },
            },
        }
        KE2.LSM = { Fetch = function() return "path/Alert.ogg" end }
        KE2.db = {
            profile = {
                DungeonTimers = {
                    Enabled = true, RoleFilterEnabled = false, MutePresetSounds = false,
                    BarGroup = {}, TextGroup = {},
                },
            },
        }
        -- Before OnEnable, with the DB populated as OnInitialize does, the
        -- validated binding and the rule-6 window already resolve for the
        -- preview and captions.
        DT2:UpdateDB()
        assert.is_not_nil(DT2:GetSpellAdmittedBinding(700))
        assert.equal(3.15, DT2:GetSpellEffectiveShowAtSeconds(700, "text"))

        DT2:OnEnable()

        local function findFrame(owner, label)
            local inst = State2.Find(DT2._state, owner, label)
            local presentations = inst and DT2._presentations[inst]
            return presentations and presentations.primary, inst
        end

        local owner = { GetEncounterID = function() return 2 end }
        DT2:OnEncounterStart(nil, 2)

        -- Table-driven: each row's reveal-floor outcome (armed-and-hidden
        -- vs immediate-show) and the running sound count.
        local rows = {
            -- Lowered window: the floor (extension+tolerance) binds.
            { key = 700, time = 10, label = "Row A", delay = 13 - 3.15, shown = false, soundsAfter = 0 },
            -- Large window: the configured value wins over the floor.
            { key = 701, time = 10, label = "Row B", delay = 13 - 10, shown = false, soundsAfter = 0 },
            -- Configured zero: the always-visible exemption.
            { key = 702, time = 10, label = "Row C", shown = true, soundsAfter = 1 },
            -- No curated showAtSeconds at all: inherits the group's zero
            -- default, same exemption via a different path.
            { key = 704, time = 10, label = "Row E", shown = true, soundsAfter = 2 },
            -- A floored window that reaches or exceeds a short total:
            -- countdown 0.1 keeps total (3.1) below the fixed 3.15 floor,
            -- so it too takes the immediate-show branch.
            { key = 700, time = 0.1, label = "Row D", shown = true, soundsAfter = 3 },
        }
        for _, row in ipairs(rows) do
            localNow = 0
            DT2:EventCallback("BigWigs_Timer", owner, row.key, row.time, nil, row.label, nil, nil, true, true)
            local frame = findFrame(owner, row.label)
            local reveal = frame._dtPresentation.revealJob
            if row.shown then
                assert.is_nil(reveal, row.label)
                assert.is_true(frame._shown, row.label)
            else
                assert.is_not_nil(reveal, row.label)
                assert.equal(row.delay, reveal.handle.delay, row.label)
                assert.is_false(frame._shown, row.label)
            end
            assert.equal(row.soundsAfter, #revealSoundCalls, row.label)
        end

        -- Positive control, opposite order: the reveal fires first (one
        -- show sound), and a later KEEP adds none.
        localNow = 0
        DT2:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Control", nil, nil, true, true)
        local frameControl, instControl = findFrame(owner, "Control")
        local recordControl = frameControl._dtPresentation
        local revealControl = recordControl.revealJob
        revealControl.handle.fn(revealControl.handle.arg)
        assert.is_true(frameControl._shown)
        assert.equal(4, #revealSoundCalls)

        localNow = 11
        DT2:EventCallback("BigWigs_StopBar", owner, "Control")
        assert.equal(4, #revealSoundCalls)   -- KEEP adds no sound once already shown.
        assert.is_true(State2.IsCurrent(DT2._state, instControl, instControl.generation,
            instControl.moduleEpoch, instControl.encounterEpoch))

        -- A repeated KEEP stays silent and idempotent.
        localNow = 11.5
        DT2:EventCallback("BigWigs_StopBar", owner, "Control")
        assert.equal(4, #revealSoundCalls)
        assert.is_true(recordControl.suppressShowSound)

        -- The frame survives the stop and keeps rendering the extended
        -- countdown (source remaining + extension) until its own expiry
        -- retires it.
        local controlStillPresent = false
        for _, f in pairs(DT2.bars) do
            if f == frameControl then controlStillPresent = true end
        end
        assert.is_true(controlStillPresent)

        localNow = 11
        frameControl:GetScript("OnUpdate")(frameControl, 0)
        assert.equal("2", frameControl._lastTimerStr:sub(1, 1))

        localNow = 13
        frameControl:GetScript("OnUpdate")(frameControl, 0)
        assert.is_nil(State2.Find(DT2._state, owner, "Control"))
        local controlPresentAfterExpiry = false
        for _, f in pairs(DT2.bars) do
            if f == frameControl then controlPresentAfterExpiry = true end
        end
        assert.is_false(controlPresentAfterExpiry)
        assert.equal(4, #revealSoundCalls)   -- no configured hide sound on this row.

        -- Hidden-at-stop: dispatch the stop BEFORE the due reveal callback
        -- runs, then run that callback. The frame shows, the forecast and
        -- its deadline are unchanged, and NO show sound plays. Only the
        -- scheduled delay is asserted, never the callbacks' execution order.
        localNow = 0
        DT2:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Hidden", nil, nil, true, true)
        local frameHidden, instHidden = findFrame(owner, "Hidden")
        local recordHidden = frameHidden._dtPresentation
        local revealHidden = recordHidden.revealJob
        local retireHidden = recordHidden.retireJob
        assert.equal(9.85, revealHidden.handle.delay)
        assert.equal(13, retireHidden.handle.delay)

        localNow = 9.85
        DT2:EventCallback("BigWigs_StopBar", owner, "Hidden")
        assert.is_false(frameHidden._shown)
        assert.is_true(recordHidden.suppressShowSound)

        revealHidden.handle.fn(revealHidden.handle.arg)
        assert.is_true(frameHidden._shown)
        assert.equal(4, #revealSoundCalls)   -- unchanged: the deferred show sound was suppressed.
        assert.is_true(State2.IsCurrent(DT2._state, instHidden, instHidden.generation,
            instHidden.moduleEpoch, instHidden.encounterEpoch))
        assert.is_false(retireHidden.handle.canceled)
        assert.equal(13, retireHidden.handle.delay)

        -- Retirement still lands at the endpoint: once shown, the retire
        -- job is a no-op and the ordinary expiry path retires the instance.
        localNow = 13
        frameHidden:GetScript("OnUpdate")(frameHidden, 0)
        assert.is_nil(State2.Find(DT2._state, owner, "Hidden"))
        local hiddenPresentAfterExpiry = false
        for _, f in pairs(DT2.bars) do
            if f == frameHidden then hiddenPresentAfterExpiry = true end
        end
        assert.is_false(hiddenPresentAfterExpiry)
        assert.equal(4, #revealSoundCalls)   -- no configured hide sound on this row.
    end)

    it("a valid Stop/Timer replacement and owner retirement cancel the estimated instance's pending work without touching another owner", function()
        local owner = { GetEncounterID = function() return 2 end }
        local otherOwner = { GetEncounterID = function() return 2 end }
        DT:OnEncounterStart(nil, 2)

        -- Equal-timestamp Timer/Stop/Timer: an early stop retires
        -- immediately, and the freed label admits a brand new Timer at the
        -- very same instant.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Burst", nil, nil, true, true)
        local firstInst = State.Find(DT._state, owner, "Burst")
        assert.is_not_nil(firstInst)
        DT:EventCallback("BigWigs_StopBar", owner, "Burst")
        assert.is_nil(State.Find(DT._state, owner, "Burst"))
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Burst", nil, nil, true, true)
        local secondInst = State.Find(DT._state, owner, "Burst")
        assert.is_not_nil(secondInst)
        assert.are_not.equal(firstInst, secondInst)

        -- KEEP-window successor: a stop inside the keep window clears the
        -- awaiting-stop entry even though the predecessor forecast stays
        -- live, so a later Timer for the same label replaces it.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Keep Window", nil, nil, true, true)
        local predecessor = State.Find(DT._state, owner, "Keep Window")
        local predecessorRecord = findPrimaryFrame(owner, "Keep Window")._dtPresentation
        local predecessorReveal = predecessorRecord.revealJob and predecessorRecord.revealJob.handle
        local predecessorRetire = predecessorRecord.retireJob and predecessorRecord.retireJob.handle

        now = 11
        DT:EventCallback("BigWigs_StopBar", owner, "Keep Window")
        assert.is_true(State.IsCurrent(DT._state, predecessor, predecessor.generation,
            predecessor.moduleEpoch, predecessor.encounterEpoch))
        assert.is_true(predecessorRecord.suppressShowSound)
        assert.is_not_nil(predecessorReveal)
        assert.is_false(predecessorReveal.canceled)
        assert.is_not_nil(predecessorRetire)
        assert.is_false(predecessorRetire.canceled)

        now = 11
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Keep Window", nil, nil, true, true)
        local successor = State.Find(DT._state, owner, "Keep Window")
        assert.are_not.equal(predecessor, successor)
        assert.is_true(successor.generation > predecessor.generation)
        assert.is_false(State.IsCurrent(DT._state, predecessor, predecessor.generation,
            predecessor.moduleEpoch, predecessor.encounterEpoch))
        assert.is_not_nil(predecessorReveal)
        assert.is_true(predecessorReveal.canceled)
        assert.is_not_nil(predecessorRetire)
        assert.is_true(predecessorRetire.canceled)
        local successorRecord = findPrimaryFrame(owner, "Keep Window")._dtPresentation
        assert.is_falsy(successorRecord.suppressShowSound)

        -- The predecessor's own reveal callback still fires after being
        -- replaced, but the record it captured is stale: it must not
        -- resurrect a frame for the retired instance.
        local barsBeforeStaleReveal = 0
        for _ in pairs(DT.bars) do barsBeforeStaleReveal = barsBeforeStaleReveal + 1 end
        local soundCallsBeforeStaleReveal = #soundCalls
        predecessorReveal.fn(predecessorReveal.arg)
        assert.equal(soundCallsBeforeStaleReveal, #soundCalls)
        local barsAfterStaleReveal = 0
        for _ in pairs(DT.bars) do barsAfterStaleReveal = barsAfterStaleReveal + 1 end
        assert.equal(barsBeforeStaleReveal, barsAfterStaleReveal)
        local predecessorRecordStillPresent = false
        for _, f in pairs(DT.bars) do
            if f._dtPresentation == predecessorRecord then predecessorRecordStillPresent = true end
        end
        assert.is_false(predecessorRecordStillPresent)

        -- Owner retirement cancels this owner's pending work without
        -- touching an unrelated owner's estimated instance.
        now = 0
        DT:EventCallback("BigWigs_Timer", otherOwner, 700, 10, nil, "Other Owner Cast", nil, nil, true, true)
        local otherInst = State.Find(DT._state, otherOwner, "Other Owner Cast")
        local otherReveal = findPrimaryFrame(otherOwner, "Other Owner Cast")._dtPresentation.revealJob
        local otherRevealHandle = otherReveal and otherReveal.handle

        -- A live spell preview is not owned work and must survive too.
        DT:ShowSpellPreview(700)
        local preview = DT.bars["__spell_preview"]
        assert.is_not_nil(preview)

        DT:EventCallback("BigWigs_StopBars", owner)
        assert.is_false(State.IsCurrent(DT._state, successor, successor.generation,
            successor.moduleEpoch, successor.encounterEpoch))
        assert.is_true(State.IsCurrent(DT._state, otherInst, otherInst.generation,
            otherInst.moduleEpoch, otherInst.encounterEpoch))
        assert.is_not_nil(otherRevealHandle)
        assert.is_false(otherRevealHandle.canceled)
        assert.equal(preview, DT.bars["__spell_preview"])
        DT:HideSpellPreview()
    end)

    it("an incoming Timer with an outstanding pilot label is refused without touching the predecessor's clock, jobs, presentation or sound flags", function()
        local owner = { GetEncounterID = function() return 2 end }
        local otherOwner = { GetEncounterID = function() return 2 end }
        DT:OnEncounterStart(nil, 2)

        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Collide", nil, nil, true, true)
        local predecessor = State.Find(DT._state, owner, "Collide")
        local predecessorRecord = findPrimaryFrame(owner, "Collide")._dtPresentation
        local predecessorReveal = predecessorRecord.revealJob and predecessorRecord.revealJob.handle
        local predecessorGeneration = predecessor.generation
        local soundCallsAfterFirst = #soundCalls

        local barsBefore = 0
        for _ in pairs(DT.bars) do barsBefore = barsBefore + 1 end

        -- A repeated Timer for the same owner/label is refused: no new
        -- instance, generation change, job cancellation or sound flag.
        now = 1
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Collide", nil, nil, true, true)
        assert.equal(predecessor, State.Find(DT._state, owner, "Collide"))
        assert.equal(predecessorGeneration, predecessor.generation)
        assert.is_not_nil(predecessorReveal)
        assert.is_false(predecessorReveal.canceled)
        assert.is_falsy(predecessorRecord.suppressShowSound)
        assert.equal(soundCallsAfterFirst, #soundCalls)

        -- Cross-key collision: the same label text is refused even when
        -- published under a different pilot key.
        now = 2
        DT:EventCallback("BigWigs_Timer", owner, 701, 10, nil, "Collide", nil, nil, true, true)
        assert.equal(predecessor, State.Find(DT._state, owner, "Collide"))
        assert.equal(soundCallsAfterFirst, #soundCalls)

        -- A distinct label for the same owner, and the same label for an
        -- unrelated owner, both proceed normally.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Collide (2)", nil, nil, true, true)
        assert.is_not_nil(State.Find(DT._state, owner, "Collide (2)"))
        now = 0
        DT:EventCallback("BigWigs_Timer", otherOwner, 700, 10, nil, "Collide", nil, nil, true, true)
        assert.is_not_nil(State.Find(DT._state, otherOwner, "Collide"))

        -- The predecessor's own independently scheduled work is unaffected
        -- and still fires normally.
        assert.is_not_nil(predecessorReveal)
        predecessorReveal.fn(predecessorReveal.arg)
        assert.is_true(findPrimaryFrame(owner, "Collide")._shown)
        assert.equal(soundCallsAfterFirst + 1, #soundCalls)

        local barsAfter = 0
        for _ in pairs(DT.bars) do barsAfter = barsAfter + 1 end
        assert.equal(barsBefore + 2, barsAfter)
    end)

    it("awaiting-stop history survives a role-filtered publication and ordinary visual expiry; only a valid matching stop clears it", function()
        local owner = { GetEncounterID = function() return 2 end }
        DT:OnEncounterStart(nil, 2)

        -- (1) Role-filtered first publication: no instance is created, yet
        -- the label is still observed.
        DT.db.RoleFilterEnabled = true
        DT:SetSpellRoleOverride(700, DT.playerRole, false)
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Filtered", nil, nil, true, true)
        assert.is_nil(State.Find(DT._state, owner, "Filtered"))
        assert.is_nil(findPrimaryFrame(owner, "Filtered"))

        -- (2) Visibility restored before the second attempt: only the
        -- awaiting-stop entry recorded in (1) can explain the continued
        -- refusal now that the role filter itself would allow it through.
        DT:SetSpellRoleOverride(700, DT.playerRole, true)
        DT.db.RoleFilterEnabled = false
        now = 1
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Filtered", nil, nil, true, true)
        assert.is_nil(State.Find(DT._state, owner, "Filtered"))

        -- (3) A valid matching stop clears the entry, letting a later
        -- publication proceed.
        DT:EventCallback("BigWigs_StopBar", owner, "Filtered")
        now = 2
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Filtered", nil, nil, true, true)
        assert.is_not_nil(State.Find(DT._state, owner, "Filtered"))
        DT:ResetSpellRoleOverride(700)
        DT.db.RoleFilterEnabled = false

        -- The disabled-row gate leaves the same awaiting-stop trail: (1) a
        -- disabled first publication, (2) still refused once re-enabled,
        -- (3) a matching stop frees it for a third Timer.
        DT:SetSpellDisabled(700, true)
        now = 3
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Disabled", nil, nil, true, true)
        assert.is_nil(State.Find(DT._state, owner, "Disabled"))
        assert.is_nil(findPrimaryFrame(owner, "Disabled"))

        DT:SetSpellDisabled(700, false)
        now = 4
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Disabled", nil, nil, true, true)
        assert.is_nil(State.Find(DT._state, owner, "Disabled"))

        DT:EventCallback("BigWigs_StopBar", owner, "Disabled")
        now = 5
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Disabled", nil, nil, true, true)
        assert.is_not_nil(State.Find(DT._state, owner, "Disabled"))

        -- Ordinary visual expiry alone grants no recovery: retire the
        -- instance through the normal OnUpdate path, then confirm the
        -- label is still refused until a real StopBar arrives.
        now = 0
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Expired", nil, nil, true, true)
        local expiredFrame = findPrimaryFrame(owner, "Expired")
        now = 13
        expiredFrame:GetScript("OnUpdate")(expiredFrame, 0)
        assert.is_nil(State.Find(DT._state, owner, "Expired"))

        now = 14
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Expired", nil, nil, true, true)
        assert.is_nil(State.Find(DT._state, owner, "Expired"))

        DT:EventCallback("BigWigs_StopBar", owner, "Expired")
        now = 15
        DT:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Expired", nil, nil, true, true)
        assert.is_not_nil(State.Find(DT._state, owner, "Expired"))
    end)

    it("a Finished timeline stop anchors a correlated pending-reveal instance and runs its reveal synchronously; a Canceled stop retires inside the tolerance", function()
        -- The module captures its timeline constants at load and the ordinary
        -- mock's Enum lacks them, so this case loads its own module instance
        -- with the full timeline Enum supplied first.
        local localNow = 0
        local anchorSoundCalls = {}
        _G.PlaySoundFile = function(file) anchorSoundCalls[#anchorSoundCalls + 1] = file end

        local DT2, KE2 = loader.loadDungeonTimers({ withEncounterData = false }, {
            CreateFrame = function() return newPlainStubFrame() end,
            GetTime = function() return localNow end,
            Enum = {
                UnitAuraSoundTrigger = { Added = "Added" },
                EncounterTimelineEventSource = { Encounter = 0 },
                EncounterTimelineEventState = { Active = 0, Paused = 1, Finished = 2, Canceled = 3 },
            },
        })
        KE2.ApplyFramePosition = function() end
        DT2.ScheduleTimer = function(_, fn, delay, arg)
            return { fn = fn, delay = delay, arg = arg, canceled = false }
        end
        DT2.CancelTimer = function(_, h) if h then h.canceled = true end end
        DT2.RegisterEvent = function() end
        DT2.UnregisterEvent = function() end
        DT2.RegisterMessage = function() end
        DT2.UnregisterMessage = function() end
        local State2 = KE2._DungeonTimerState

        local function findFrame(owner, label)
            local inst = State2.Find(DT2._state, owner, label)
            local presentations = inst and DT2._presentations[inst]
            return presentations and presentations.primary, inst
        end

        KE2.EncounterData = {
            [2] = {
                name = "Explicit Boss", dungeon = "Explicit Dungeon", timerPolicy = "explicit",
                spells = {
                    -- showAtSeconds below extension+tolerance: the rule-6
                    -- floor (3.15) binds, so the reveal starts hidden and
                    -- pending -- the case this fixture needs.
                    [700] = { name = "Row A", castType = "begincast", castDuration = 3,
                              showAtSeconds = 1, sound = "Alert", timerSource = {
                                  kind = "Timer", isCooldown = true, policy = "estimated-impact",
                                  spanMode = "remaining-only", stopTolerance = 0.15,
                                  collisionPolicy = "refuse-unresolved-label",
                                  anchor = "timeline-finished",
                              } },
                },
            },
        }
        KE2.LSM = { Fetch = function() return "path/Alert.ogg" end }
        KE2.db = {
            profile = {
                DungeonTimers = {
                    Enabled = true, RoleFilterEnabled = false, MutePresetSounds = false,
                    BarGroup = {}, TextGroup = {},
                },
            },
        }
        DT2:OnEnable()

        local owner = { GetEncounterID = function() return 2 end }
        DT2:OnEncounterStart(nil, 2)

        -- Finished: receipt 0, provider deadline 10, extension 3, floored
        -- showWindow 3.15 -> total 13, initial reveal deadline 9.85. The
        -- ADDED handler records the correlated event on the same receipt
        -- tick with the receipt's own duration, so it resolves at the stop.
        localNow = 0
        DT2:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Finished Cue", nil, nil, true, true)
        DT2:OnEncounterTimelineEventAdded(nil, { source = 0, id = 42, duration = 10, maxQueueDuration = 20 })
        local frame, inst = findFrame(owner, "Finished Cue")
        assert.is_not_nil(frame)
        local record = frame._dtPresentation
        local originalRevealHandle = record.revealJob.handle
        assert.equal(9.85, originalRevealHandle.delay)
        assert.equal(13, record.retireJob.handle.delay)
        assert.is_false(frame._shown)

        -- Stop before the reveal ever fires manually, so it is still
        -- pending. The floor makes the rescheduled reveal already due
        -- (deadline <= the anchor instant minus tolerance), so anchoring
        -- runs it synchronously rather than leaving it scheduled.
        localNow = 6
        _G.C_EncounterTimeline = { GetEventState = function() return 2 end }  -- Finished
        DT2:EventCallback("BigWigs_StopBar", owner, "Finished Cue")

        assert.is_true(State2.IsCurrent(DT2._state, inst, inst.generation, inst.moduleEpoch, inst.encounterEpoch))
        assert.is_true(originalRevealHandle.canceled)
        assert.is_nil(record.revealJob)
        assert.is_true(frame._shown)
        assert.equal(1, #anchorSoundCalls)
        assert.is_falsy(record.suppressShowSound)
        assert.is_not_nil(record.retireJob)
        assert.equal(9, record.retireJob.deadline)
        assert.equal(3, record.retireJob.handle.delay)

        -- A fresh instance on its own receipt tick, so its own timeline record.
        localNow = 100
        DT2:EventCallback("BigWigs_Timer", owner, 700, 10, nil, "Canceled Cue", nil, nil, true, true)
        DT2:OnEncounterTimelineEventAdded(nil, { source = 0, id = 99, duration = 10, maxQueueDuration = 20 })
        assert.is_not_nil(State2.Find(DT2._state, owner, "Canceled Cue"))

        localNow = 110
        _G.C_EncounterTimeline = { GetEventState = function() return 3 end }  -- Canceled
        DT2:EventCallback("BigWigs_StopBar", owner, "Canceled Cue")
        assert.is_nil(State2.Find(DT2._state, owner, "Canceled Cue"))
    end)

    it("the StartBar timeline ID in callback argument 10 identifies the kept duplicate so its Finished anchors; the same ID only in argument 9 is a different field and the duplicate stays ambiguous", function()
        for _, case in ipairs({
            { name = "argument 10", inTimelineField = true },
            { name = "argument 9", inTimelineField = false },
        }) do
            local m = loadTimelineModule()
            local states = {}
            _G.C_EncounterTimeline = { GetEventState = function(id) return states[id] end }
            -- One publication in its live order: event added, then its start bar and Timer.
            local function publish(eventId)
                m.DT:OnEncounterTimelineEventAdded(nil, { source = 0, id = eventId, duration = 12, maxQueueDuration = 6 })
                local otherField, timelineField = eventId, nil
                if case.inTimelineField then otherField, timelineField = nil, eventId end
                m.DT:EventCallback("BigWigs_StartBar", m.owner, 701, "Nova (5)", 12, nil, true, nil,
                    otherField, timelineField)
                m.DT:EventCallback("BigWigs_Timer", m.owner, 701, 12, nil, "Nova (5)", 5, nil, true, true)
            end
            m.clock.now = 100
            publish(419)
            m.DT:EventCallback("BigWigs_StopBar", m.owner, "Nova (5)")
            publish(421)
            local inst = m.find("Nova (5)")
            assert.is_not_nil(inst, case.name)

            states[421] = 2
            m.clock.now = 112.5
            m.DT:EventCallback("BigWigs_StopBar", m.owner, "Nova (5)")
            if case.inTimelineField then
                assert.equal(12.5, inst.anchorElapsed, case.name)
            else
                assert.is_nil(inst.anchorElapsed, case.name)
                assert.equal(inst, (m.find("Nova (5)")), case.name)
            end
        end
    end)

    it("hold resolution at forecast zero refuses no-event/ambiguous/no-maxqueue/secret-state/terminal/gone/no-enum and retires, schedules the hold job on success, and creates it suspended on a paused instance", function()
        local m = loadTimelineModule()
        local refusals = {
            { name = "no-event", eventId = nil, state = 0 },
            { name = "ambiguous", eventId = 900, duplicate = true, state = 0 },
            { name = "no-maxqueue", eventId = 901, maxQueue = { __secret = true }, state = 0 },
            { name = "secret-state", eventId = 902, state = { __secret = true } },
            { name = "terminal", eventId = 903, state = 2 },
            { name = "gone", eventId = 904, state = nil },
        }
        for i, case in ipairs(refusals) do
            m.clock.now = i * 100
            local label = "Refused " .. case.name
            local maxQueue = 6
            if case.maxQueue ~= nil then maxQueue = case.maxQueue end
            local inst, frame = m.publish(701, label, 10, case.eventId, maxQueue)
            if case.duplicate then
                m.DT:OnEncounterTimelineEventAdded(nil, { source = 0, id = case.eventId + 500, duration = 10, maxQueueDuration = 6 })
            end
            _G.C_EncounterTimeline = { GetEventState = function() return case.state end }
            local resolved, _, reason = m.DT:_ResolveHold(inst)
            assert.is_nil(resolved, case.name)
            assert.equal(case.name, reason, case.name)
            -- Forecast zero: remaining 10 + extension 3.
            m.clock.now = i * 100 + 13
            m.tick(frame)
            assert.is_nil(m.State.Find(m.DT._state, m.owner, label), case.name)
            assert.is_nil(inst.holdDeadline, case.name)
            assert.is_nil(m.findJob("hold", inst), case.name)
        end

        -- no-enum: an anchor-capable module loaded without the state enum
        -- refuses before reading anything and retires at forecast zero.
        local n = loadTimelineModule({ timelineEnum = false })
        _G.C_EncounterTimeline = { GetEventState = function() return 0 end }
        n.clock.now = 0
        local noEnumInst, noEnumFrame = n.publish(701, "No Enum", 10, 905, 6)
        local noEnumResolved, _, noEnumReason = n.DT:_ResolveHold(noEnumInst)
        assert.is_nil(noEnumResolved)
        assert.equal("no-enum", noEnumReason)
        n.clock.now = 13
        n.tick(noEnumFrame)
        assert.is_nil(n.State.Find(n.DT._state, n.owner, "No Enum"))
        assert.is_nil(noEnumInst.holdDeadline)

        -- Success: Active event, queue 6 -> deadline 10 + 6 + 0.5 = 16.5;
        -- the job fires 3.5 s after the zero crossing.
        m.clock.now = 1000
        local inst, frame = m.publish(701, "Held", 10, 910, 6)
        _G.C_EncounterTimeline = { GetEventState = function() return 0 end }
        m.clock.now = 1013
        m.tick(frame)
        assert.equal(16.5, inst.holdDeadline)
        local job = m.findJob("hold", inst)
        assert.is_not_nil(job)
        assert.equal(3.5, job.handle.delay)
        assert.is_not_nil(m.State.Find(m.DT._state, m.owner, "Held"))
        m.clock.now = 1016.5
        job.handle.fn(job.handle.arg)
        assert.is_nil(m.State.Find(m.DT._state, m.owner, "Held"))
        assert.is_nil(m.DT._presentations[inst])
        assert.is_nil(m.DT._holdJobs[inst])

        -- Paused at eligibility: the clock froze exactly at forecast zero,
        -- so the next update is hold-eligible while paused. The job is owned
        -- but has no timer until Resume, and 3.5 s of effective time remain.
        m.clock.now = 2000
        local pausedInst, pausedFrame = m.publish(701, "Paused Hold", 10, 920, 6)
        m.clock.now = 2013
        m.DT:EventCallback("BigWigs_PauseBar", m.owner, "Paused Hold")
        -- The timeline event itself reports Paused: the resolver must accept it.
        _G.C_EncounterTimeline = { GetEventState = function() return 1 end }
        m.clock.now = 2014
        local timersBefore = #m.timers
        m.tick(pausedFrame)
        assert.equal(16.5, pausedInst.holdDeadline)
        local suspended = m.findJob("hold", pausedInst)
        assert.is_not_nil(suspended)
        assert.is_nil(suspended.handle)
        assert.equal(timersBefore, #m.timers)
        m.clock.now = 2020
        m.DT:EventCallback("BigWigs_ResumeBar", m.owner, "Paused Hold")
        assert.is_not_nil(suspended.handle)
        assert.equal(3.5, suspended.handle.delay)
        assert.equal("keep", m.State.ClassifyExpiry(pausedInst, 2023.4))
        assert.equal("retire", m.State.ClassifyExpiry(pausedInst, 2023.5))
        m.clock.now = 2023.5
        suspended.handle.fn(suspended.handle.arg)
        assert.is_nil(m.State.Find(m.DT._state, m.owner, "Paused Hold"))
    end)

    it("a Finished stop during the hold anchors from the stop before the bound, cancels the hold job "
        .. "and drains past the former deadline; at the bound it retires; "
        .. "Canceled before anchor retires", function()
        local m = loadTimelineModule()
        _G.C_EncounterTimeline = { GetEventState = function() return 0 end }
        m.clock.now = 0
        local inst, frame = m.publish(701, "Late Finish", 10, 930, 6)
        m.clock.now = 9
        m.tick(frame)
        assert.is_not_nil(tonumber(frame._lastTimerStr), "numeric before forecast zero")
        m.clock.now = 13
        m.tick(frame)
        local holdJob = m.findJob("hold", inst)
        assert.is_not_nil(holdJob)
        assert.equal(16.5, inst.holdDeadline)
        assert.equal("", frame._lastTimerStr, "blank while held")

        -- Finished at 15: anchored total 18 lies beyond the former 16.5 bound.
        m.clock.now = 15
        _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Late Finish")
        assert.equal(15, inst.anchorElapsed)
        assert.is_nil(inst.holdDeadline)
        assert.is_true(holdJob.handle.canceled)
        assert.is_nil(m.findJob("hold", inst))
        assert.is_nil(m.DT._holdJobs[inst])
        m.clock.now = 17.9
        m.tick(frame)
        assert.is_not_nil(m.State.Find(m.DT._state, m.owner, "Late Finish"))
        assert.is_not_nil(tonumber(frame._lastTimerStr), "numeric after the anchor")
        m.clock.now = 18
        m.tick(frame)
        assert.is_nil(m.State.Find(m.DT._state, m.owner, "Late Finish"))

        -- At the bound: retire, never anchor.
        m.clock.now = 100
        local lateInst, lateFrame = m.publish(701, "Too Late", 10, 931, 6)
        _G.C_EncounterTimeline = { GetEventState = function() return 0 end }
        m.clock.now = 113
        m.tick(lateFrame)
        assert.equal(16.5, lateInst.holdDeadline)
        m.clock.now = 116.5
        _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Too Late")
        assert.is_nil(m.State.Find(m.DT._state, m.owner, "Too Late"))
        assert.is_nil(lateInst.anchorElapsed)
        assert.is_nil(m.findJob("hold", lateInst))

        -- Canceled during the hold, before any anchor: retire.
        m.clock.now = 200
        local canceledInst, canceledFrame = m.publish(701, "Canceled Hold", 10, 932, 6)
        _G.C_EncounterTimeline = { GetEventState = function() return 0 end }
        m.clock.now = 213
        m.tick(canceledFrame)
        assert.is_not_nil(m.findJob("hold", canceledInst))
        m.clock.now = 214
        _G.C_EncounterTimeline = { GetEventState = function() return 3 end }
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Canceled Hold")
        assert.is_nil(m.State.Find(m.DT._state, m.owner, "Canceled Hold"))
        assert.is_nil(m.findJob("hold", canceledInst))
    end)

    it("a Finished stop while paused cancels the hold job, resumes clock and state at the stop, anchors, drains afterward, and a later stop on the anchored instance is ignored", function()
        local m = loadTimelineModule()
        _G.C_EncounterTimeline = { GetEventState = function() return 0 end }
        m.clock.now = 0
        local inst, frame = m.publish(701, "Paused Finish", 10, 940, 6)
        m.clock.now = 13
        m.tick(frame)
        local holdJob = m.findJob("hold", inst)
        assert.is_not_nil(holdJob)

        m.clock.now = 14
        m.DT:EventCallback("BigWigs_PauseBar", m.owner, "Paused Finish")
        assert.equal("paused", inst.state)
        assert.is_true(holdJob.handle.canceled)

        -- Finished at 16 after 2 s paused: effective 14 at the stop.
        m.clock.now = 16
        _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Paused Finish")
        assert.equal("running", inst.state)
        assert.is_nil(inst.sourceClock.pausedAt)
        assert.equal(2, inst.sourceClock.accumulatedPause)
        assert.equal(14, inst.anchorElapsed)
        assert.is_nil(inst.holdDeadline)
        assert.is_nil(m.findJob("hold", inst))
        assert.is_nil(m.DT._holdJobs[inst])

        -- Anchored total 17 elapsed = wall 19; a repeated stop is ignored.
        assert.equal("keep", m.State.ClassifyExpiry(inst, 18.9))
        assert.equal("retire", m.State.ClassifyExpiry(inst, 19))
        m.clock.now = 17
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Paused Finish")
        assert.equal(14, inst.anchorElapsed)
        assert.is_not_nil(m.State.Find(m.DT._state, m.owner, "Paused Finish"))
    end)

    it("cast-start watch arms only for castConfirm rows on anchor, refuses secret/non-string/non-boss units, confirms the first boss start inside the window once, closes on a start past the window, and refuses when two watches are armed", function()
        local m = loadTimelineModule()
        _G.C_EncounterTimeline = { GetEventState = function() return 2 end }

        -- Debug observation can share START without owning a confirmation watch.
        m.clock.now = 0
        local plainInst = m.publish(701, "No Watch", 10, 950, 6)
        m.clock.now = 9
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "No Watch")
        assert.equal(9, plainInst.anchorElapsed)
        assert.is_nil(m.DT._castWatches[plainInst])
        assert.is_nil(m.DT._unitCastHolders.UNIT_SPELLCAST_START.watch)

        -- castConfirm row: the anchor at wall 109 arms a window to 110.5.
        m.clock.now = 100
        local inst = m.publish(700, "Watched", 10, 951, 6)
        m.clock.now = 109
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Watched")
        assert.equal(9, inst.anchorElapsed)
        local watch = m.DT._castWatches[inst]
        assert.is_not_nil(watch)
        assert.equal(110.5, watch.windowEnd)
        assert.is_true(m.DT._unitCastHolders.UNIT_SPELLCAST_START.watch)

        local refused = {
            { name = "secret unit", unit = { __secret = true } },
            { name = "secret boss-shaped unit", unit = "boss9" },
            { name = "non-string unit", unit = 7 },
            { name = "player unit", unit = "player" },
            { name = "nameplate unit", unit = "nameplate3" },
        }
        m.clock.now = 109.5
        for _, case in ipairs(refused) do
            m.DT:OnUnitCastStart(nil, case.unit)
            assert.equal(9, inst.anchorElapsed, case.name)
            assert.is_falsy(inst.confirmed, case.name)
            assert.is_not_nil(m.DT._castWatches[inst], case.name)
        end

        -- First boss start inside the window confirms once and drops the
        -- watch (job canceled, START released); the second is ignored.
        m.clock.now = 110
        m.DT:OnUnitCastStart(nil, "boss1")
        assert.equal(10, inst.anchorElapsed)
        assert.is_true(inst.confirmed)
        assert.is_nil(m.DT._castWatches[inst])
        assert.is_true(watch.job.handle.canceled)
        assert.is_nil(m.DT._unitCastHolders.UNIT_SPELLCAST_START.watch)
        m.clock.now = 110.2
        m.DT:OnUnitCastStart(nil, "boss2")
        assert.equal(10, inst.anchorElapsed)

        -- A start past the window end (before its job fired) never re-bases
        -- and closes the watch.
        m.clock.now = 200
        local lateInst = m.publish(700, "Late Start", 10, 952, 6)
        m.clock.now = 209
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Late Start")
        assert.is_not_nil(m.DT._castWatches[lateInst])
        m.clock.now = 210.6
        m.DT:OnUnitCastStart(nil, "boss1")
        assert.equal(9, lateInst.anchorElapsed)
        assert.is_falsy(lateInst.confirmed)
        assert.is_nil(m.DT._castWatches[lateInst])

        -- Two armed in-window watches (A ends 310.5, B ends 311.5): neither
        -- confirms. Once A is overdue and its job has not yet run, B alone
        -- is armed and confirms.
        m.clock.now = 300
        local a = m.publish(700, "Armed A", 10, 953, 6)
        m.clock.now = 302
        local b = m.publish(700, "Armed B", 10, 954, 6)
        m.clock.now = 309
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Armed A")
        m.clock.now = 310
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Armed B")
        assert.is_not_nil(m.DT._castWatches[a])
        assert.is_not_nil(m.DT._castWatches[b])
        m.clock.now = 310.25
        m.DT:OnUnitCastStart(nil, "boss1")
        assert.equal(9, a.anchorElapsed)
        assert.equal(8, b.anchorElapsed)
        assert.is_falsy(a.confirmed)
        assert.is_falsy(b.confirmed)
        m.clock.now = 310.75
        m.DT:OnUnitCastStart(nil, "boss1")
        assert.is_nil(m.DT._castWatches[a])
        assert.equal(9, a.anchorElapsed)
        assert.equal(8.75, b.anchorElapsed)
        assert.is_true(b.confirmed)

        -- A stale in-window watch (its instance retired in state without the
        -- module's release, as a generation or epoch change leaves it) closes
        -- as retired and never re-bases; the current watch alone confirms.
        m.clock.now = 400
        local stale = m.publish(700, "Stale", 10, 955, 6)
        m.clock.now = 402
        local current = m.publish(700, "Current", 10, 956, 6)
        m.clock.now = 409
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Stale")
        m.clock.now = 410
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Current")
        m.State.Retire(m.DT._state, stale)
        assert.is_not_nil(m.DT._castWatches[stale])
        m.clock.now = 410.25
        m.DT:OnUnitCastStart(nil, "boss1")
        assert.is_nil(m.DT._castWatches[stale])
        assert.equal(9, stale.anchorElapsed)
        assert.is_falsy(stale.confirmed)
        assert.equal(8.25, current.anchorElapsed)
        assert.is_true(current.confirmed)
    end)

    it("a castConfirm bar anchored before forecast zero or during the hold re-bases once on the boss cast start, moves a pending retire job to each new total, and drains to the confirmed zero with the hold job gone", function()
        local m = loadTimelineModule()
        -- Ordering 1 is the observed FRONTAL shape (Finished 0.8 s before
        -- the cast); the reveal is still pending at the stop and the retire
        -- job is moved twice. Ordering 2 anchors during the hold, after the
        -- retire job fired on the shown bar.
        local orderings = {
            { name = "finished before zero", finishedAt = 8, confirmAt = 9, anchoredTotal = 12, confirmedTotal = 13, retirePending = true },
            { name = "finished during hold", finishedAt = 15, confirmAt = 16, anchoredTotal = 19, confirmedTotal = 20, retirePending = false },
        }
        for i, o in ipairs(orderings) do
            local base = (i - 1) * 100
            local label = "Slam " .. i
            _G.C_EncounterTimeline = { GetEventState = function() return 0 end }
            m.clock.now = base
            local inst, frame = m.publish(700, label, 10, 960 + i, 6)
            local record = frame._dtPresentation
            -- total 14, floored showWindow 4.15: reveal at 9.85, retire at 14.
            assert.equal(9.85, record.revealJob.handle.delay, o.name)
            assert.equal(14, record.retireJob.handle.delay, o.name)
            if not o.retirePending then
                m.clock.now = base + 9.85
                record.revealJob.handle.fn(record.revealJob.handle.arg)
                assert.is_true(frame._shown, o.name)
                -- The retire job fires at forecast zero and leaves a shown
                -- bar to its update path; the next update resolves the hold.
                m.clock.now = base + 14
                record.retireJob.handle.fn(record.retireJob.handle.arg)
                assert.is_nil(record.retireJob, o.name)
                assert.is_not_nil(m.State.Find(m.DT._state, m.owner, label), o.name)
                m.tick(frame)
                assert.equal(16.5, inst.holdDeadline, o.name)
                assert.is_not_nil(m.findJob("hold", inst), o.name)
            end

            m.clock.now = base + o.finishedAt
            _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
            m.DT:EventCallback("BigWigs_StopBar", m.owner, label)
            assert.equal(o.finishedAt, inst.anchorElapsed, o.name)
            assert.is_nil(inst.holdDeadline, o.name)
            assert.is_nil(m.findJob("hold", inst), o.name)
            assert.is_not_nil(m.DT._castWatches[inst], o.name)
            assert.is_true(frame._shown, o.name)
            assert.is_nil(record.revealJob, o.name)
            if o.retirePending then
                assert.equal(o.anchoredTotal, record.retireJob.deadline, o.name)
                assert.equal(4, record.retireJob.handle.delay, o.name)
            end
            assert.equal("keep", m.State.ClassifyExpiry(inst, base + o.anchoredTotal - 0.1), o.name)
            assert.equal("retire", m.State.ClassifyExpiry(inst, base + o.anchoredTotal), o.name)

            -- Boss cast start 1.0 s after Finished: origin moves by 1.0.
            m.clock.now = base + o.confirmAt
            m.DT:OnUnitCastStart(nil, "boss1")
            assert.equal(o.confirmAt, inst.anchorElapsed, o.name)
            assert.is_true(inst.confirmed, o.name)
            if o.retirePending then
                assert.equal(o.confirmedTotal, record.retireJob.deadline, o.name)
                assert.equal(4, record.retireJob.handle.delay, o.name)
            end

            m.clock.now = base + o.confirmedTotal - 0.1
            m.tick(frame)
            assert.is_not_nil(m.State.Find(m.DT._state, m.owner, label), o.name)
            m.clock.now = base + o.confirmedTotal
            m.tick(frame)
            assert.is_nil(m.State.Find(m.DT._state, m.owner, label), o.name)
            assert.is_nil(m.DT._castWatches[inst], o.name)
        end
    end)

    it("an arrival after the observation deadline closes the window without counting and releases no shared registration, while encounter end and zone exit drop an armed watch and an open window and release the unit-cast events", function()
        local m = loadTimelineModule()
        -- ENCOUNTER_START registered the shield feature's events (row 702).
        assert.equal(1, m.events.count(m.events.registered, "UNIT_SPELLCAST_CHANNEL_START"))
        _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
        m.clock.now = 0
        local inst = m.publish(700, "Teardown", 10, 970, 6)
        m.clock.now = 9
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Teardown")
        assert.is_not_nil(m.DT._castWatches[inst])
        -- The DEBUG_DT2 gate is in the anchor arm; the window opens directly here.
        m.DT:_OpenObservationWindow(inst, m.clock.now)
        assert.is_not_nil(m.DT._observeWindows[inst])
        assert.equal(1, m.events.count(m.events.registered, "UNIT_SPELLCAST_START"))
        assert.equal(1, m.events.count(m.events.registered, "UNIT_SPELLCAST_CHANNEL_START"))

        -- One channel start reaches the shield path (nothing armed) and the window.
        local window = m.DT._observeWindows[inst]
        m.DT:OnUnitChannelStart(nil, "boss1")
        assert.equal(1, window.count)

        -- A channel start after the 3.0 s deadline, before the window job
        -- ran, closes the window uncounted. Closing releases neither slot:
        -- the watch holds START, the shield holds CHANNEL_START.
        m.clock.now = 12.1
        m.DT:OnUnitChannelStart(nil, "boss1")
        assert.is_nil(m.DT._observeWindows[inst])
        assert.equal(1, window.count)
        assert.is_true(window.job.handle.canceled)
        assert.equal(0, m.events.count(m.events.unregistered, "UNIT_SPELLCAST_START"))
        assert.equal(0, m.events.count(m.events.unregistered, "UNIT_SPELLCAST_CHANNEL_START"))

        -- Encounter end drops both and unregisters both events once each.
        m.DT:_OpenObservationWindow(inst, m.clock.now)
        m.DT:OnEncounterEnd()
        assert.is_nil(m.DT._castWatches[inst])
        assert.is_nil(m.DT._observeWindows[inst])
        assert.equal(1, m.events.count(m.events.unregistered, "UNIT_SPELLCAST_START"))
        assert.equal(1, m.events.count(m.events.unregistered, "UNIT_SPELLCAST_CHANNEL_START"))
        assert.is_nil(next(m.DT._unitCastHolders.UNIT_SPELLCAST_START))
        assert.is_nil(next(m.DT._unitCastHolders.UNIT_SPELLCAST_CHANNEL_START))

        -- Zone exit on a fresh encounter: RetireOrdinaryWork drops both and
        -- releases START; the shield keeps CHANNEL_START until encounter end.
        m.DT:OnEncounterStart(nil, 2)
        m.clock.now = 100
        local inst2 = m.publish(700, "Zone Exit", 10, 971, 6)
        m.clock.now = 109
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Zone Exit")
        m.DT:_OpenObservationWindow(inst2, m.clock.now)
        m.DT:OnPlayerEnteringWorld()
        assert.is_nil(m.DT._castWatches[inst2])
        assert.is_nil(m.DT._observeWindows[inst2])
        assert.equal(2, m.events.count(m.events.unregistered, "UNIT_SPELLCAST_START"))
        assert.equal(1, m.events.count(m.events.unregistered, "UNIT_SPELLCAST_CHANNEL_START"))
        assert.is_not_nil(m.DT._unitCastHolders.UNIT_SPELLCAST_CHANNEL_START.shield)
        -- A following encounter without a shield binding releases the shield's events.
        m.DT:OnEncounterStart(nil, 99)
        assert.equal(2, m.events.count(m.events.unregistered, "UNIT_SPELLCAST_CHANNEL_START"))
        assert.is_nil(m.DT._unitCastHolders.UNIT_SPELLCAST_CHANNEL_START.shield)
        assert.is_nil(m.DT._unitCastHolders.UNIT_SPELLCAST_CHANNEL_STOP.shield)
    end)

    -- AceAddon still runs OnDisable after a refused OnEnable, so the tables
    -- OnDisable walks must exist even when the profile has the module off,
    -- and its layout calls must not build the empty groups.
    -- BigWigsLoader is read at call time, so it is set after the load.
    it("a refused enable and a later disable register nothing, create no frame and raise no error", function()
        local registered = {}
        local framesCreated = 0
        local DT3, KE3 = loader.loadDungeonTimers({ withEncounterData = false }, {
            CreateFrame = function()
                framesCreated = framesCreated + 1
                return newPlainStubFrame()
            end,
            GetTime = function() return now end,
        })
        framesCreated = 0
        KE3.ApplyFramePosition = function() end
        DT3.RegisterEvent = function(_, event) registered[#registered + 1] = event end
        DT3.UnregisterEvent = function() end
        DT3.ScheduleTimer = function() end
        DT3.CancelTimer = function() end
        KE3.EncounterData = {}
        KE3.db = { profile = { DungeonTimers = { Enabled = false, BarGroup = {}, TextGroup = {} } } }
        local savedLoader = _G.BigWigsLoader
        _G.BigWigsLoader = {
            RegisterMessage = function(_, event) registered[#registered + 1] = event end,
            UnregisterMessage = function() end,
        }

        DT3:OnEnable()
        local ok, err = pcall(DT3.OnDisable, DT3)
        _G.BigWigsLoader = savedLoader

        assert.is_true(ok, tostring(err))
        assert.same({}, registered)
        assert.equal(0, framesCreated)
    end)

    -- Count cues load the real module through loadTimelineModule. The count
    -- templates and the renames are stateless stubs; an unregistered locale
    -- returns nil, as the provider's GetLocale does. The secret rows use its
    -- declared { __secret = true } guard stub, which proves only that KE's
    -- guard is present, never native secrecy.
    local KICK_KEY, PULL_KEY = 1310358, 1307894
    local KICK_CUE, PULL_CUE = "cue:2:kicks", "cue:2:pull"

    local function countApi(amount)
        return {
            GetLocale = function(_, name)
                if name ~= "BigWigs: Common" then return nil end
                return { count_amount = amount, count = "%s (%d)" }
            end,
        }
    end

    local function loadCountModule(interruptResult, ordinalSounds)
        local m = loadTimelineModule({ encounterData = function(data)
            data[2].phaseCues = {
                kicks = { name = "Kicks", iconOverride = 134400, duration = interruptResult and 4 or 1.5, ordinals = 3,
                          interruptResult = interruptResult, ordinalSounds = ordinalSounds,
                          display = "text", displayText = "KICK", showAtSeconds = 0, sound = "Alert",
                          source = { kind = "Message", key = KICK_KEY } },
                pull = { name = "Pull", iconOverride = 134400, duration = 3, messageCount = 1, maxPerPull = 1,
                         display = "text", displayText = "AOE", showAtSeconds = 0, sound = "Alert",
                         source = { kind = "Message", key = PULL_KEY } },
            }
        end })
        local renames = { [KICK_KEY] = "Toxic Atrophy", [PULL_KEY] = "Ravenous Stomp" }
        m.owner.GetRename = function(_, key)
            if not renames[key] then error("no rename entry") end
            return renames[key]
        end
        _G.BigWigsAPI = countApi("%s (%d/%d)")
        return m
    end

    local function cueTexts(m, slotKey)
        local texts = {}
        for _, frame in pairs(m.DT.bars) do
            local record = frame._dtPresentation
            if record and record.synthetic == "cue" and record.slotKey == slotKey then
                texts[#texts + 1] = frame.baseText
            end
        end
        return texts
    end

    local function kickTexts(m) return cueTexts(m, KICK_CUE) end

    local function sendKick(m, message)
        m.DT:EventCallback("BigWigs_Message", m.owner, KICK_KEY, message)
    end

    local function sendPull(m, message)
        m.DT:EventCallback("BigWigs_Message", m.owner, PULL_KEY, message)
    end

    local function loadInterruptModule()
        local m = loadCountModule({ ordinal = 3, unit = "boss1", displayText = "DONE",
            duration = 1.5, color = { 0, 1, 0 } })
        m.castBarID = 10
        _G.UnitCastingInfo = function()
            return nil, nil, nil, nil, nil, nil, nil, nil, { __secret = true }, m.castBarID
        end
        finally(function() _G.UnitCastingInfo, _G.BigWigsAPI = nil, nil end)
        return m
    end

    local function interruptKick(m, unit, id)
        m.DT:OnUnitCastInterrupted(nil, unit, { __secret = true }, { __secret = true }, { __secret = true }, id)
    end

    it("a matched third-kick interrupt replaces the cue with a silent result once, including duplicate Messages", function()
        local m = loadInterruptModule()
        sendKick(m, "Toxic Atrophy (3/3)")
        local sounds = #soundCalls
        local kick = m.DT._slotPresentations[m.owner].cue[KICK_CUE]
        m.clock.now = 0.5
        sendKick(m, "Toxic Atrophy (3/3)")
        assert.equal(kick, m.DT._slotPresentations[m.owner].cue[KICK_CUE])
        assert.equal(sounds, #soundCalls)
        m.clock.now = 1
        interruptKick(m, "boss2", 10)
        interruptKick(m, "boss1", 11)
        interruptKick(m, "boss9", 10)
        interruptKick(m, "boss1", { __secret = true })
        assert.same({ "KICK 3" }, kickTexts(m))
        interruptKick(m, "boss1", 10)
        assert.same({}, kickTexts(m))
        assert.same({ "DONE" }, cueTexts(m, KICK_CUE .. "#ended"))
        local result = m.DT._slotPresentations[m.owner].cue[KICK_CUE .. "#ended"]
        m.clock.now = 1.2
        interruptKick(m, "boss1", 10)
        for _, id in ipairs({ 10, false }) do
            m.castBarID = id or nil
            sendKick(m, "Toxic Atrophy (3/3)")
            assert.equal(result, m.DT._slotPresentations[m.owner].cue[KICK_CUE .. "#ended"])
        end
        assert.same({}, kickTexts(m))
        assert.equal(sounds, #soundCalls)
        m.clock.now = 2.6
        m.tick(result)
        assert.same({}, cueTexts(m, KICK_CUE .. "#ended"))
        m.castBarID = 11
        sendKick(m, "Toxic Atrophy (3/3)")
        assert.same({ "KICK 3" }, kickTexts(m))
    end)

    it("earlier kicks, missing cast identity and natural expiry do not create interrupt success", function()
        for _, case in ipairs({ "earlier", "missing", "secret", "natural" }) do
            local m = loadInterruptModule()
            if case == "missing" then m.castBarID = nil end
            if case == "secret" then m.castBarID = { __secret = true } end
            local ordinal = case == "earlier" and 2 or 3
            sendKick(m, ("Toxic Atrophy (%d/3)"):format(ordinal))
            if case ~= "natural" then interruptKick(m, "boss1", 10) end
            assert.same({ "KICK " .. ordinal }, kickTexts(m), case)
            local frame = m.DT._slotPresentations[m.owner].cue[KICK_CUE]
            m.clock.now = 4
            m.tick(frame)
            for _, h in ipairs(m.timers) do if not h.canceled then h.fn(h.arg) end end
            interruptKick(m, "boss1", 10)
            assert.same({}, kickTexts(m), case)
            assert.same({}, cueTexts(m, KICK_CUE .. "#ended"), case)
            assert.is_nil(next(m.DT._cueInterrupts), case)
            assert.is_nil(next(m.DT._unitCastHolders.UNIT_SPELLCAST_INTERRUPTED), case)
        end
    end)

    it("matched failure events complete early stops once across mixed failure and interrupt deliveries", function()
        for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET" }) do
            local m = loadInterruptModule()
            sendKick(m, "Toxic Atrophy (3/3)")
            m.DT:OnUnitCastFailed(event, "boss1", { __secret = true }, { __secret = true }, 11)
            assert.same({ "KICK 3" }, kickTexts(m))
            m.clock.now = 1
            m.DT:OnUnitCastFailed(event, "boss1", { __secret = true }, { __secret = true }, 10)
            assert.same({}, kickTexts(m))
            assert.same({ "DONE" }, cueTexts(m, KICK_CUE .. "#ended"))
            local result = m.DT._slotPresentations[m.owner].cue[KICK_CUE .. "#ended"]
            m.clock.now = 1.2
            interruptKick(m, "boss1", 10)
            m.DT:OnUnitCastFailed(event, "boss1", nil, nil, 10)
            assert.equal(result, m.DT._slotPresentations[m.owner].cue[KICK_CUE .. "#ended"])
        end
    end)

    it("replacement and lifecycle cleanup prevent late interrupts and canceled jobs from reviving a result", function()
        local actions = {
            replacement = function(m) m.castBarID = 11; sendKick(m, "Toxic Atrophy (3/3)") end,
            owner = function(m) m.DT:EventCallback("BigWigs_StopBars", m.owner) end,
            encounter = function(m) m.DT:OnEncounterEnd() end,
            start = function(m) m.DT:OnEncounterStart(nil, 2) end,
            profile = function(m) m.DT:OnProfileBoundary() end,
            world = function(m) m.DT:OnPlayerEnteringWorld() end,
            disable = function(m) m.DT:OnDisable() end,
        }
        for name, action in pairs(actions) do
            local m = loadInterruptModule()
            sendKick(m, "Toxic Atrophy (3/3)")
            local old = next(m.DT._cueInterrupts)
            m.clock.now = 1
            action(m)
            old.job.action()
            interruptKick(m, "boss1", 10)
            assert.same({}, cueTexts(m, KICK_CUE .. "#ended"), name)
            if name == "replacement" then
                assert.same({ "KICK 3" }, kickTexts(m))
                interruptKick(m, "boss1", 11)
                assert.same({ "DONE" }, cueTexts(m, KICK_CUE .. "#ended"))
            else
                assert.is_nil(next(m.DT._cueInterrupts), name)
                assert.is_nil(next(m.DT._unitCastHolders.UNIT_SPELLCAST_INTERRUPTED), name)
            end
        end
    end)

    it("an ordinal cue plays its matching voice once per delivery and honors master mute without dropping its label", function()
        local m = loadCountModule(nil, { "Kick 1", "Kick 2", "Kick 3" })
        m.KE.LSM = { Fetch = function(_, _kind, key) return "path/" .. key .. ".ogg" end }
        finally(function() _G.BigWigsAPI = nil end)
        for i, n in ipairs({ 1, 2, 3, 1, 1 }) do
            local before = #soundCalls
            sendKick(m, ("Toxic Atrophy (%d/3)"):format(n))
            assert.same({ "KICK " .. n }, kickTexts(m), "delivery " .. i)
            assert.equal(before + 1, #soundCalls, "delivery " .. i)
            assert.equal("path/Kick " .. n .. ".ogg", soundCalls[#soundCalls], "delivery " .. i)
        end
        m.DT.db.MutePresetSounds = true
        local before = #soundCalls
        sendKick(m, "Toxic Atrophy (2/3)")
        assert.same({ "KICK 2" }, kickTexts(m))
        assert.equal(before, #soundCalls)
    end)

    it("an ordinal cue refuses a secret, unmatched or unreadable payload before any change and leaves the shown ordinal", function()
        local cases = {
            { name = "secret message", message = { __secret = true } },
            { name = "unmatched message", message = "Toxic Atrophy (4/3)" },
            { name = "no provider API", api = false },
            { name = "unregistered locale", api = { GetLocale = function() return nil end } },
            { name = "secret template", api = countApi({ __secret = true }) },
            { name = "rename raises", renameRaises = true },
        }
        finally(function() _G.BigWigsAPI = nil end)
        for _, case in ipairs(cases) do
            local m = loadCountModule()
            sendKick(m, "Toxic Atrophy (2/3)")
            if case.api ~= nil then _G.BigWigsAPI = case.api or nil end
            if case.renameRaises then m.owner.GetRename = function() error("no rename entry") end end
            local sounds = #soundCalls
            local admitted = m.DT._state.cueCounts[2][KICK_CUE]
            sendKick(m, case.message or "Toxic Atrophy (3/3)")
            assert.same({ "KICK 2" }, kickTexts(m), case.name)
            assert.equal(sounds, #soundCalls, case.name)
            assert.equal(admitted, m.DT._state.cueCounts[2][KICK_CUE], case.name)
        end
    end)

    it("a counted cue shows only the Message equal to the provider's count text for its number, and another count refuses before the cap", function()
        local m = loadCountModule()
        finally(function() _G.BigWigsAPI = nil end)
        local sounds = #soundCalls
        sendPull(m, "Ravenous Stomp (2)")
        assert.same({}, cueTexts(m, PULL_CUE))
        assert.equal(sounds, #soundCalls)
        assert.is_nil(m.DT._state.cueCounts[2] and m.DT._state.cueCounts[2][PULL_CUE])
        sendPull(m, "Ravenous Stomp (1)")
        assert.same({ "AOE" }, cueTexts(m, PULL_CUE))
        assert.equal(sounds + 1, #soundCalls)
    end)

    -- The final ordinal exposes replay order; uncapped sounds expose duplicate
    -- delivery. The unmarked row checks that unrelated receipts cannot interfere.
    local FRESH_KEY = 703

    local function loadPullModule()
        local m = loadTimelineModule({ encounterData = function(data, contract)
            local source = contract({ pullReceipt = true })
            source.anchor = nil
            data[2].spells[FRESH_KEY] = { name = "Fresh Row", castType = "cast", castDuration = 0,
                                          showAtSeconds = 0, timerSource = source }
            data[2].phaseCues = {
                kicks = { name = "Kicks", iconOverride = 134400, duration = 1.5, ordinals = 3, pullReceipt = true,
                          display = "text", displayText = "KICK", showAtSeconds = 0, sound = "Alert",
                          source = { kind = "Message", key = KICK_KEY } },
            }
        end })
        m.owner.GetRename = function(_, key)
            if key ~= KICK_KEY then error("no rename entry") end
            return "Toxic Atrophy"
        end
        _G.BigWigsAPI = countApi("%s (%d/%d)")
        return m
    end

    it("valid marked pull receipts held before the encounter start replay once, in arrival order, for that encounter only, up to four per source, unless a stop, boundary or age voids them; refused or unmarked receipts take no room or label", function()
        local noisy = {}
        for i = 1, 9 do noisy[i] = "noise" end
        noisy[10], noisy[11] = "k1", "k2"
        local cases = {
            { name = "provider first", before = { "k1", "k2" }, kicks = { "KICK 2" }, sounds = 2 },
            { name = "start first", after = { "k1", "k2" }, kicks = { "KICK 2" }, sounds = 2 },
            { name = "held estimate", before = { "fresh" }, fresh = true },
            { name = "estimate stopped before start", before = { "fresh", "stop" } },
            { name = "unmarked receipts take no room", before = noisy, kicks = { "KICK 2" }, sounds = 2 },
            { name = "another encounter starts", before = { "k1", "k2" }, start = 99 },
            { name = "encounter end between", before = { "k1", "k2", "end" } },
            { name = "world change between", before = { "k1", "k2", "world" } },
            { name = "profile change between", before = { "k1", "k2", "profile" } },
            { name = "older than the window", before = { "k1", "k2" }, at = 49 },
            { name = "fifth valid receipt from one source", before = { "k1", "k2", "k3", "k1", "k2" },
              kicks = { "KICK 1" }, sounds = 4 },
            { name = "refused Messages take no room", before = { "ksecret", "k4", "k4", "k4", "k4", "k1", "k2" },
              kicks = { "KICK 2" }, sounds = 2 },
            { name = "malformed estimate takes no label", before = { "freshZero", "fresh" }, fresh = true },
            { name = "secret-field estimate takes no label", before = { "freshSecretIcon", "fresh" }, fresh = true },
        }
        local steps = {
            k1 = function(m) sendKick(m, "Toxic Atrophy (1/3)") end,
            k2 = function(m) sendKick(m, "Toxic Atrophy (2/3)") end,
            k3 = function(m) sendKick(m, "Toxic Atrophy (3/3)") end,
            k4 = function(m) sendKick(m, "Toxic Atrophy (4/3)") end,
            ksecret = function(m) sendKick(m, { __secret = true }) end,
            fresh = function(m) m.publish(FRESH_KEY, "Fresh (1)", 6) end,
            freshZero = function(m) m.publish(FRESH_KEY, "Fresh (1)", 0) end,
            freshSecretIcon = function(m)
                m.DT:EventCallback("BigWigs_Timer", m.owner, FRESH_KEY, 6, nil, "Fresh (1)", nil,
                    { __secret = true }, true, true)
            end,
            stop = function(m) m.DT:EventCallback("BigWigs_StopBar", m.owner, "Fresh (1)") end,
            noise = function(m)
                m.noiseCount = (m.noiseCount or 0) + 1
                m.publish(701, "Noise " .. m.noiseCount, 10)
            end,
            ["end"] = function(m) m.DT:OnEncounterEnd() end,
            world = function(m) m.DT:OnPlayerEnteringWorld() end,
            profile = function(m) m.DT:OnProfileBoundary() end,
        }
        finally(function() _G.BigWigsAPI = nil end)
        for _, case in ipairs(cases) do
            local m = loadPullModule()
            m.DT:OnEncounterEnd()
            m.clock.now = case.at or 50
            local sounds = #soundCalls
            for _, step in ipairs(case.before or {}) do steps[step](m) end
            m.clock.now = 50
            m.DT:OnEncounterStart(nil, case.start or 2)
            for _, step in ipairs(case.after or {}) do steps[step](m) end
            assert.same(case.kicks or {}, kickTexts(m), case.name)
            assert.equal(sounds + (case.sounds or 0), #soundCalls, case.name)
            assert.equal(case.fresh == true, (m.find("Fresh (1)")) ~= nil, case.name)
            assert.is_nil((m.find("Noise 1")), case.name)
            assert.same({}, m.DT._pullHold, case.name)
        end
    end)

    local CUE_WINDOW, CUE_PHASE = "cue:3:window", "cue:3:phase"

    local function cueOwner()
        return { GetEncounterID = function() return 3 end }
    end

    local function cueJob(cueKey)
        for job in pairs(DT._jobs) do
            if job.kind == "cue" and job.cueKey == cueKey then return job end
        end
        return nil
    end

    local function cueFire(job) job.handle.fn(job.handle.arg) end

    local function cueTick(frame) frame:GetScript("OnUpdate")(frame, 0) end

    local function cueFrames(slotKey)
        return findSynthetic("cue", function(record) return record.slotKey == slotKey end)
    end

    local function sendWarning(who, text)
        DT:EventCallback("BigWigs_Message", who, 900, text)
    end

    local function sendPhaseTimer(who, label)
        DT:EventCallback("BigWigs_Timer", who, 800, 15, nil, label, nil, nil, false, true)
    end

    local function cuePrimaryFrame(who, label)
        local inst = State.FindCue(DT._state, who, CUE_PHASE, label)
        local presentations = inst and DT._presentations[inst]
        return presentations and presentations.primary
    end

    it("a Message cue appears at its end minus the reveal, ends at Message plus lead plus duration, and is drawn with the user's display mode and text", function()
        local owner = cueOwner()
        DT:OnEncounterStart(nil, 3)
        DT:SetSpellShowAtOverride(CUE_WINDOW, 5)
        DT:SetSpellDisplayOverride(CUE_WINDOW, "text")
        DT:SetSpellDisplayTextOverride(CUE_WINDOW, "MY WINDOW")

        now = 100
        sendWarning(owner, "warning")
        local job = cueJob(CUE_WINDOW)
        assert.equal(117, job.deadline)
        assert.equal(0, #cueFrames(CUE_WINDOW))

        now = 117
        cueFire(job)
        local shown = cueFrames(CUE_WINDOW)
        assert.equal(1, #shown)
        assert.equal("text", shown[1].frame.displayMode)
        assert.equal("MY WINDOW", shown[1].frame.baseText)
        assert.equal(5, shown[1].frame.totalDuration)
    end)

    it("a second Message removes a showing or pending Message cue occurrence at receipt and plans one from the later Message; a disabled or role-filtered cue spawns nothing", function()
        for _, case in ipairs({ { name = "showing", second = 105 }, { name = "pending", second = 101 } }) do
            local owner = cueOwner()
            DT:OnEncounterStart(nil, 3)
            now = 100
            sendWarning(owner, "first")
            local first = cueJob(CUE_WINDOW)
            if case.second > 102 then
                now = 102
                cueFire(first)
            end
            now = case.second
            sendWarning(owner, "second")
            assert.equal(0, #cueFrames(CUE_WINDOW), case.name)
            assert.is_true(first.handle == nil or first.handle.canceled, case.name)
            assert.equal(case.second + 2, cueJob(CUE_WINDOW).deadline, case.name)
            DT:OnEncounterEnd()
        end

        local filters = {
            { name = "disabled",
              apply = function() DT:SetSpellDisabled(CUE_WINDOW, true) end,
              undo = function() DT:SetSpellDisabled(CUE_WINDOW, false) end },
            { name = "role-filtered",
              apply = function()
                  DT.db.RoleFilterEnabled = true
                  DT:SetSpellRoleOverride(CUE_WINDOW, DT.playerRole, false)
              end,
              undo = function() DT.db.RoleFilterEnabled = false end },
        }
        for _, case in ipairs(filters) do
            local owner = cueOwner()
            DT:OnEncounterStart(nil, 3)
            case.apply()
            now = 200
            sendWarning(owner, "filtered")
            now = 202
            cueFire(cueJob(CUE_WINDOW))
            assert.equal(0, #findSynthetic("cue"), case.name)
            case.undo()
            DT:OnEncounterEnd()
        end
    end)

    it("an admitted Message for a disabled cue uses one of the pull's activations, the Message over the cap plans nothing and leaves the showing occurrence, and a new pull shows again", function()
        local owner = cueOwner()
        DT:OnEncounterStart(nil, 3)
        DT:SetSpellDisabled(CUE_WINDOW, true)
        now = 100
        sendWarning(owner, "one")
        DT:SetSpellDisabled(CUE_WINDOW, false)
        now = 110
        sendWarning(owner, "two")
        now = 112
        cueTick(cueFrames(CUE_WINDOW .. "#prepare")[1].frame)
        cueFire(cueJob(CUE_WINDOW))
        local showing = cueFrames(CUE_WINDOW)[1].frame

        now = 115
        sendWarning(owner, "three")
        assert.is_nil(cueJob(CUE_WINDOW))
        assert.equal(0, #cueFrames(CUE_WINDOW .. "#prepare"))
        assert.is_true(barsContains(showing))

        DT:OnEncounterEnd()
        DT:OnEncounterStart(nil, 3)
        now = 200
        sendWarning(owner, "next pull")
        assert.is_not_nil(cueJob(CUE_WINDOW))
        assert.equal(1, #cueFrames(CUE_WINDOW .. "#prepare"))
    end)

    it("a second non-cooldown Timer with another label retires the first Timer cue occurrence at receipt, a stop for the displaced label changes nothing and the cooldown row on the key is untouched; with one label shared, a row and a cue or two cues keep separate occurrences in every receipt order, and a pause or stop reaches only the identity whose Timer was received last, also once that one has expired or was filtered", function()
        local CUE_PHASE_B = "cue:3:phase_b"
        local function sendCooldown(who, label)
            DT:EventCallback("BigWigs_Timer", who, 800, 30, nil, label, nil, nil, true, true)
        end
        local function sendPhaseTimerB(who, label)
            DT:EventCallback("BigWigs_Timer", who, 801, 15, nil, label, nil, nil, false, true)
        end
        local function stop(who, label) DT:EventCallback("BigWigs_StopBar", who, label) end

        local owner = cueOwner()
        DT:OnEncounterStart(nil, 3)
        now = 0
        sendCooldown(owner, "Cooldown (1)")
        sendPhaseTimer(owner, "Phase (1)")
        local first = State.FindCue(DT._state, owner, CUE_PHASE, "Phase (1)")
        assert.equal(CUE_PHASE, first.binding.cueKey)

        now = 5
        sendPhaseTimer(owner, "Phase (2)")
        assert.equal("retired", first.state)
        assert.is_nil(DT._presentations[first])
        local second = State.FindCue(DT._state, owner, CUE_PHASE, "Phase (2)")
        assert.is_not_nil(cuePrimaryFrame(owner, "Phase (2)"))

        stop(owner, "Phase (1)")
        assert.equal("running", second.state)
        assert.is_not_nil(cuePrimaryFrame(owner, "Phase (2)"))
        assert.is_not_nil(findPrimaryFrame(owner, "Cooldown (1)"))
        DT:OnEncounterEnd()

        -- Both bars renamed to one text: neither receipt retires the other,
        -- and the stop goes to the one received last.
        local orders = {
            { name = "row then cue", rowFirst = true, stopped = "cue" },
            { name = "cue then row", rowFirst = false, stopped = "row" },
        }
        for _, case in ipairs(orders) do
            local sameOwner = cueOwner()
            DT:OnEncounterStart(nil, 3)
            now = 100
            if case.rowFirst then
                sendCooldown(sameOwner, "Rage (1)")
                sendPhaseTimer(sameOwner, "Rage (1)")
            else
                sendPhaseTimer(sameOwner, "Rage (1)")
                sendCooldown(sameOwner, "Rage (1)")
            end
            local row = State.Find(DT._state, sameOwner, "Rage (1)")
            local cue = State.FindCue(DT._state, sameOwner, CUE_PHASE, "Rage (1)")
            assert.equal("running", row.state, case.name)
            assert.equal("running", cue.state, case.name)
            assert.is_not_nil(findPrimaryFrame(sameOwner, "Rage (1)"), case.name)
            assert.is_not_nil(cuePrimaryFrame(sameOwner, "Rage (1)"), case.name)

            now = 105
            stop(sameOwner, "Rage (1)")
            assert.equal(case.stopped == "row" and "retired" or "running", row.state, case.name)
            assert.equal(case.stopped == "cue" and "retired" or "running", cue.state, case.name)
            DT:OnEncounterEnd()
        end

        -- The cue received last keeps the label after it has no instance:
        -- a pause or stop never falls back to the row it displaced, and a
        -- later row publication takes the label back.
        local gone = {
            { name = "expired", publish = function(who)
                sendPhaseTimer(who, "Rage (1)")
                now = 215
                cueTick(cuePrimaryFrame(who, "Rage (1)"))
            end },
            { name = "filtered", publish = function(who)
                DT:SetSpellDisabled(CUE_PHASE, true)
                sendPhaseTimer(who, "Rage (1)")
                DT:SetSpellDisabled(CUE_PHASE, false)
            end },
        }
        for _, case in ipairs(gone) do
            local goneOwner = cueOwner()
            DT:OnEncounterStart(nil, 3)
            now = 200
            sendCooldown(goneOwner, "Rage (1)")
            local row = State.Find(DT._state, goneOwner, "Rage (1)")
            case.publish(goneOwner)
            assert.is_nil(State.FindCue(DT._state, goneOwner, CUE_PHASE, "Rage (1)"), case.name)

            now = 216
            DT:EventCallback("BigWigs_PauseBar", goneOwner, "Rage (1)")
            assert.equal("running", row.state, case.name .. ": pause")
            DT:EventCallback("BigWigs_ResumeBar", goneOwner, "Rage (1)")
            stop(goneOwner, "Rage (1)")
            assert.equal("running", row.state, case.name .. ": stop")

            now = 217
            sendCooldown(goneOwner, "Rage (1)")
            local republished = State.Find(DT._state, goneOwner, "Rage (1)")
            now = 222
            stop(goneOwner, "Rage (1)")
            assert.equal("retired", republished.state, case.name .. ": republished row")
            DT:OnEncounterEnd()
        end

        -- Two cue identities given one label: neither receipt retires the
        -- other, the stop reaches the later one, and a repeat of the label
        -- on one cue replaces only that cue's occurrence.
        local twoOwner = cueOwner()
        DT:OnEncounterStart(nil, 3)
        now = 300
        sendPhaseTimer(twoOwner, "Rage (1)")
        sendPhaseTimerB(twoOwner, "Rage (1)")
        local cueA = State.FindCue(DT._state, twoOwner, CUE_PHASE, "Rage (1)")
        local cueB = State.FindCue(DT._state, twoOwner, CUE_PHASE_B, "Rage (1)")
        assert.equal("running", cueA.state)
        assert.equal("running", cueB.state)

        now = 305
        stop(twoOwner, "Rage (1)")
        assert.equal("running", cueA.state)
        assert.equal("retired", cueB.state)

        sendPhaseTimer(twoOwner, "Rage (1)")
        local repeated = State.FindCue(DT._state, twoOwner, CUE_PHASE, "Rage (1)")
        assert.equal("retired", cueA.state)
        now = 310
        stop(twoOwner, "Rage (1)")
        assert.equal("retired", repeated.state)
    end)

    it("a Sequel cue is planned at a zero-extension parent's Finished whichever of the stop and the expiry job runs first at the deadline and not at the hold bound, is replaced only by a later parent anchor, leaves an extended parent's countdown running to its corrected end, and a numeric Sequel child still loses its slot on a same-label republish", function()
        local m = loadTimelineModule({ encounterData = function(data, contract)
            local spells = data[2].spells
            spells[710] = { name = "Zero Parent", castType = "begincast", castDuration = 0,
                            showAtSeconds = 0, timerSource = contract() }
            spells[730] = { name = "Extended Parent", castType = "begincast", castDuration = 4,
                            showAtSeconds = 0, timerSource = contract() }
            spells[720] = { name = "Numeric Parent", castType = "begincast", castDuration = 0,
                            showAtSeconds = 0, timerSource = contract() }
            spells[721] = { name = "Numeric Child", castType = "begincast", castDuration = 5,
                            showAtSeconds = 0, timerSource = { kind = "Sequel", parent = 720, after = 10 } }
            data[2].phaseCues = {
                lockout = { name = "Lockout", iconOverride = 134400, duration = 10, display = "text",
                            displayText = "LOCKED", showAtSeconds = 0,
                            source = { kind = "Sequel", parent = 710, after = 0 } },
                prepare = { name = "Prepare", iconOverride = 134400, duration = 4, display = "text",
                            displayText = "SOON", showAtSeconds = 0,
                            source = { kind = "Sequel", parent = 730, after = 0 } },
            }
        end })
        local FINISHED, CANCELED = 2, 3
        local states = {}
        _G.C_EncounterTimeline = { GetEventState = function(id) return states[id] end }
        local LOCKOUT = "cue:2:lockout"
        local function syntheticRecord(kind, slotKey)
            for _, frame in pairs(m.DT.bars) do
                local record = frame._dtPresentation
                if record and record.synthetic == kind and (not slotKey or record.slotKey == slotKey) then
                    return record
                end
            end
            return nil
        end
        local function stop(label) m.DT:EventCallback("BigWigs_StopBar", m.owner, label) end

        -- Zero extension, stop processed first, exactly at the deadline.
        states[501] = FINISHED
        m.clock.now = 0
        m.publish(710, "Wave (1)", 10, 501, 6)
        m.clock.now = 10
        stop("Wave (1)")
        assert.equal(10, syntheticRecord("cue", LOCKOUT).clock.receivedAt)

        -- Zero extension, expiry job processed first and reading Finished:
        -- it holds, and the stop that follows anchors.
        states[502] = FINISHED
        m.clock.now = 20
        local held = m.publish(710, "Wave (2)", 10, 502, 6)
        m.clock.now = 30
        local expiry = m.findJob("hold", held)
        expiry.handle.fn(expiry.handle.arg)
        assert.equal("running", held.state)
        stop("Wave (2)")
        assert.equal(30, syntheticRecord("cue", LOCKOUT).clock.receivedAt)

        -- At the hold bound (10 + 6 + 0.5) the Finished is refused. That
        -- new-label receipt and its retirement leave the follow-up alone.
        states[503] = FINISHED
        m.clock.now = 40
        m.publish(710, "Wave (3)", 10, 503, 6)
        m.clock.now = 56.5
        stop("Wave (3)")
        assert.is_nil((m.find("Wave (3)")))
        assert.equal(30, syntheticRecord("cue", LOCKOUT).clock.receivedAt)

        -- A same-label receipt and its Canceled stop leave it alone too.
        states[504] = CANCELED
        m.clock.now = 60
        m.publish(710, "Wave (2)", 12, 504, 6)
        m.clock.now = 62
        stop("Wave (2)")
        assert.equal(30, syntheticRecord("cue", LOCKOUT).clock.receivedAt)

        -- A later parent occurrence reaching its anchor ends it and plans its own.
        states[505] = FINISHED
        m.clock.now = 70
        m.publish(710, "Wave (4)", 10, 505, 6)
        m.clock.now = 75
        stop("Wave (4)")
        assert.equal(75, syntheticRecord("cue", LOCKOUT).clock.receivedAt)

        -- Extended parent: the follow-up is planned at the anchor and the
        -- parent's own countdown runs on to the anchor plus its extension.
        states[601] = FINISHED
        m.clock.now = 100
        m.publish(730, "Rage (1)", 10, 601, 6)
        m.clock.now = 110
        stop("Rage (1)")
        assert.equal(110, syntheticRecord("cue", "cue:2:prepare").clock.receivedAt)
        local _, parentFrame = m.find("Rage (1)")
        m.clock.now = 113.9
        m.tick(parentFrame)
        assert.is_not_nil((m.find("Rage (1)")))
        m.clock.now = 114
        m.tick(parentFrame)
        assert.is_nil((m.find("Rage (1)")))

        states[701] = FINISHED
        m.clock.now = 200
        m.publish(720, "Slam (1)", 10, 701, 6)
        m.clock.now = 209
        stop("Slam (1)")
        local child = syntheticRecord("sequel")
        assert.is_true(m.State.IsSlotCurrent(m.DT._state, m.owner, "sequel", child.slotKey, child.generation))
        m.clock.now = 210
        m.publish(720, "Slam (1)", 10, 702, 6)
        assert.is_false(m.State.IsSlotCurrent(m.DT._state, m.owner, "sequel", child.slotKey, child.generation))
    end)

    -- Unlike cueFrames, reads a separately loaded module instance.
    local function cueFramesOf(loaded, slotKey)
        local found = {}
        for _, frame in pairs(loaded.DT.bars) do
            local record = frame._dtPresentation
            if record and record.synthetic == "cue" and record.slotKey == slotKey then
                found[#found + 1] = frame
            end
        end
        return found
    end

    it("a Sequel cue with ending text shows it at the window's natural end for what is left of its "
        .. "interval and nothing once that has passed, shows none when a later parent anchor or an owner "
        .. "teardown removes the live window, and those remove an ending already showing", function()
        local LOCKOUT = "cue:2:lockout"
        local ENDED = LOCKOUT .. "#ended"
        local function loadCue()
            local loaded = loadTimelineModule({ encounterData = function(data, contract)
                data[2].spells[710] = { name = "Zero Parent", castType = "begincast", castDuration = 0,
                                        showAtSeconds = 0, timerSource = contract() }
                data[2].phaseCues = {
                    lockout = { name = "Lockout", iconOverride = 134400, duration = 10, display = "text",
                                displayText = "LOCKED", showAtSeconds = 0,
                                endedText = "ENDED", endedDuration = 2,
                                source = { kind = "Sequel", parent = 710, after = 0 } },
                }
            end })
            _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
            return loaded
        end
        local function anchorParent(loaded, label, eventId, publishAt, stopAt)
            loaded.clock.now = publishAt
            loaded.publish(710, label, 10, eventId, 6)
            loaded.clock.now = stopAt
            loaded.DT:EventCallback("BigWigs_StopBar", loaded.owner, label)
        end
        -- The window runs from the parent's anchor at 10 to 20.
        local function openWindow(loaded)
            anchorParent(loaded, "Wave (1)", 501, 0, 10)
            return cueFramesOf(loaded, LOCKOUT)[1]
        end

        for _, late in ipairs({ { at = 20, left = 2 }, { at = 21, left = 1 }, { at = 23 } }) do
            local natural = loadCue()
            local window = openWindow(natural)
            assert.is_not_nil(window, "window, end processed at " .. late.at)
            natural.clock.now = late.at
            natural.tick(window)
            local ended = cueFramesOf(natural, ENDED)
            if late.left then
                assert.equal(1, #ended, "end processed at " .. late.at)
                assert.equal("ENDED", ended[1].baseText, "end processed at " .. late.at)
                assert.equal(late.left, ended[1].totalDuration, "end processed at " .. late.at)
                assert.is_true(ended[1].staticLabel, "end processed at " .. late.at)
            else
                assert.equal(0, #ended, "end processed at " .. late.at)
            end
        end

        local interrupts = {
            { name = "later parent anchor",
              run = function(loaded, at) anchorParent(loaded, "Wave (2)", 502, at, at + 1) end },
            { name = "owner teardown",
              run = function(loaded, at)
                  loaded.clock.now = at
                  loaded.DT:EventCallback("BigWigs_StopBars", loaded.owner)
              end },
        }
        for _, case in ipairs(interrupts) do
            local live = loadCue()
            assert.is_not_nil(openWindow(live), case.name .. ": window")
            case.run(live, 12)
            assert.equal(0, #cueFramesOf(live, ENDED), case.name .. ": interrupted while live")

            local shown = loadCue()
            local window = openWindow(shown)
            assert.is_not_nil(window, case.name .. ": window")
            shown.clock.now = 20
            shown.tick(window)
            assert.equal(1, #cueFramesOf(shown, ENDED), case.name .. ": natural end")
            case.run(shown, 20.5)
            assert.equal(0, #cueFramesOf(shown, ENDED), case.name .. ": interrupted while the ending shows")
        end
    end)

    it("a Sequel cue naming a row in endsOnAnchor never shows beside that row's own Sequel window: the row's anchor ends a pending or visible occurrence without ending text from a displayed or track-only row; the cue's parent anchoring while the window is drawn or admitted and pending plans nothing and ends nothing; it plans again past the window's end before cleanup, past an overdue reveal, and beside a disabled pending window; and drawing a window admitted later ends the cue", function()
        local LEAP, LOCKOUT = "cue:2:leap", "cue:2:lockout"
        -- Both parents publish at 0; the drop parent's anchor at 15 plans the
        -- leap window from 20.1 to 23.1.
        local function loadLeap(waveDisabled)
            local loaded = loadTimelineModule({ encounterData = function(data, contract)
                local spells = data[2].spells
                spells[740] = { name = "Drop Parent", castType = "begincast", castDuration = 5,
                                showAtSeconds = 0, timerSource = contract() }
                spells[741] = { name = "Wave Parent", castType = "begincast", castDuration = 0,
                                showAtSeconds = 0, disabled = waveDisabled, timerSource = contract() }
                data[2].phaseCues = {
                    leap = { name = "Leap", iconOverride = 134400, duration = 8.1, display = "text",
                             displayText = "LEAP", showAtSeconds = 3, endsOnAnchor = 741,
                             source = { kind = "Sequel", parent = 740, after = 0 } },
                    lockout = { name = "Lockout", iconOverride = 134400, duration = 10, display = "text",
                                displayText = "LOCKED", showAtSeconds = 0,
                                endedText = "ENDED", endedDuration = 2,
                                source = { kind = "Sequel", parent = 741, after = 0 } },
                }
            end })
            local states = {}
            _G.C_EncounterTimeline = { GetEventState = function(id) return states[id] end }
            loaded.states = states
            loaded.clock.now = 0
            loaded.publish(740, "Drops (1)", 15, 801, 6)
            loaded.publish(741, "Wave (1)", 22, 802, 6)
            states[801] = 2
            loaded.clock.now = 15
            loaded.DT:EventCallback("BigWigs_StopBar", loaded.owner, "Drops (1)")
            return loaded
        end
        local function leapPlan(loaded)
            for job in pairs(loaded.DT._jobs) do
                if job.cueKey == LEAP then return job end
            end
            return nil
        end
        local function anchorWave(loaded, at)
            loaded.states[802] = 2
            loaded.clock.now = at
            loaded.DT:EventCallback("BigWigs_StopBar", loaded.owner, "Wave (1)")
        end
        local function anchorDrops(loaded, label, eventId, at)
            loaded.states[eventId] = 2
            loaded.clock.now = at
            loaded.publish(740, label, 1, eventId, 6)
            loaded.clock.now = at + 1
            loaded.DT:EventCallback("BigWigs_StopBar", loaded.owner, label)
        end

        for _, mode in ipairs({ { name = "displayed row", disabled = false },
                                { name = "track-only row", disabled = true } }) do
            local pending = loadLeap(mode.disabled)
            assert.is_not_nil(leapPlan(pending), mode.name .. ": leap planned")
            anchorWave(pending, 17)
            assert.is_nil(leapPlan(pending), mode.name .. ": pending leap ended")
            assert.equal(0, #cueFramesOf(pending, LEAP), mode.name .. ": no leap drawn")
            assert.equal(1, #cueFramesOf(pending, LOCKOUT), mode.name .. ": lockout planned at the anchor")

            local visible = loadLeap(mode.disabled)
            local plan = leapPlan(visible)
            visible.clock.now = 21
            plan.handle.fn(plan.handle.arg)
            assert.equal(1, #cueFramesOf(visible, LEAP), mode.name .. ": leap visible")
            anchorWave(visible, 21.5)
            assert.equal(0, #cueFramesOf(visible, LEAP), mode.name .. ": visible leap ended")
            assert.equal(0, #cueFramesOf(visible, LEAP .. "#ended"), mode.name .. ": no ending text")
            local window = cueFramesOf(visible, LOCKOUT)[1]
            assert.is_not_nil(window, mode.name .. ": lockout planned at the anchor")

            anchorDrops(visible, "Drops (2)", 803, 22)
            assert.equal(1, #cueFramesOf(visible, LOCKOUT), mode.name .. ": parent anchor ends nothing")
            assert.is_nil(leapPlan(visible), mode.name .. ": no leap beside the shown lockout")

            -- The window ended at 31.5; its frame has not been updated since.
            anchorDrops(visible, "Drops (3)", 804, 31.5)
            assert.equal(window, cueFramesOf(visible, LOCKOUT)[1], mode.name .. ": frame not yet cleaned up")
            assert.is_not_nil(leapPlan(visible), mode.name .. ": next leap planned past the window's end")
        end

        -- The lockout reveals 4 s before its end: planned at 17 for 23, ending at 27.
        local function loadDelayed(lockoutDisabled)
            local loaded = loadLeap(false)
            loaded.DT.db.SpellShowAtOverrides = { [LOCKOUT] = 4 }
            if lockoutDisabled then loaded.DT.db.SpellDisabled = { [LOCKOUT] = true } end
            anchorWave(loaded, 17)
            return loaded
        end
        local function lockoutPlan(loaded)
            for job in pairs(loaded.DT._jobs) do
                if job.cueKey == LOCKOUT then return job end
            end
            return nil
        end

        local enabled = loadDelayed(false)
        assert.is_not_nil(lockoutPlan(enabled), "lockout reveal pending")
        anchorDrops(enabled, "Drops (2)", 803, 18)
        assert.is_nil(leapPlan(enabled), "no leap beside an admitted pending lockout")

        local overdue = loadDelayed(false)
        anchorDrops(overdue, "Drops (2)", 803, 27)
        assert.is_not_nil(lockoutPlan(overdue), "reveal job still undispatched")
        assert.is_not_nil(leapPlan(overdue), "an overdue reveal past the window's end does not block")

        local filtered = loadDelayed(true)
        anchorDrops(filtered, "Drops (2)", 803, 18)
        assert.is_not_nil(leapPlan(filtered), "a disabled lockout's pending reveal does not block")
        filtered.DT.db.SpellDisabled[LOCKOUT] = nil
        filtered.clock.now = 23
        local reveal = lockoutPlan(filtered)
        reveal.handle.fn(reveal.handle.arg)
        assert.equal(1, #cueFramesOf(filtered, LOCKOUT), "lockout admitted again and drawn")
        assert.is_nil(leapPlan(filtered), "drawing the lockout ends the planned leap")
        assert.equal(0, #cueFramesOf(filtered, LEAP), "no leap drawn")
    end)

    it("a stored time offset on a cue key does not move the cue's end", function()
        local owner = cueOwner()
        DT:OnEncounterStart(nil, 3)
        DT.db.SpellTimeOffsets = { [CUE_WINDOW] = 5, [CUE_PHASE] = 5 }

        now = 100
        sendWarning(owner, "warning")
        now = 102
        cueFire(cueJob(CUE_WINDOW))
        assert.equal(20, cueFrames(CUE_WINDOW)[1].frame.totalDuration)

        sendPhaseTimer(owner, "Phase (1)")
        assert.equal(0, State.FindCue(DT._state, owner, CUE_PHASE, "Phase (1)").binding.extension)
        assert.equal(15, cuePrimaryFrame(owner, "Phase (1)").totalDuration)
    end)

    it("a Message cue draws its preparation text at receipt and drops it at the phase start, draws its ended text at the natural end for what is left of its interval, also when the reveal itself runs after that end, and neither leg plays a sound", function()
        local owner = cueOwner()
        DT:OnEncounterStart(nil, 3)
        now = 100
        sendWarning(owner, "warning")
        local prepare = cueFrames(CUE_WINDOW .. "#prepare")
        assert.equal(1, #prepare)
        assert.equal("SOON", prepare[1].frame.baseText)
        assert.equal("text", prepare[1].frame.displayMode)
        assert.equal(0, #soundCalls)

        now = 102
        cueTick(prepare[1].frame)
        assert.equal(0, #cueFrames(CUE_WINDOW .. "#prepare"))
        cueFire(cueJob(CUE_WINDOW))
        assert.equal(1, #soundCalls)

        now = 122
        cueTick(cueFrames(CUE_WINDOW)[1].frame)
        assert.equal(0, #cueFrames(CUE_WINDOW))
        assert.equal(2, #soundCalls)
        local ended = cueFrames(CUE_WINDOW .. "#ended")
        assert.equal(1, #ended)
        assert.equal("ENDED", ended[1].frame.baseText)
        assert.is_true(ended[1].frame.staticLabel)

        assert.equal(2, ended[1].frame.totalDuration)

        now = 124
        cueTick(ended[1].frame)
        assert.equal(0, #cueFrames(CUE_WINDOW .. "#ended"))
        assert.equal(2, #soundCalls)
        DT:OnEncounterEnd()

        -- The interval is fixed at the window's end (222), not at the frame
        -- that notices the expiry.
        for _, late in ipairs({ { by = 1, left = 1 }, { by = 3 } }) do
            local lateOwner = cueOwner()
            DT:OnEncounterStart(nil, 3)
            now = 200
            sendWarning(lateOwner, "warning")
            now = 202
            cueFire(cueJob(CUE_WINDOW))
            now = 222 + late.by
            cueTick(cueFrames(CUE_WINDOW)[1].frame)
            local lateEnded = cueFrames(CUE_WINDOW .. "#ended")
            if late.left then
                assert.equal(late.left, lateEnded[1].frame.totalDuration, "processed " .. late.by .. " s late")
            else
                assert.equal(0, #lateEnded, "processed after the interval")
            end
            DT:OnEncounterEnd()
        end

        -- A reveal dispatched after the window's end (322) draws no window
        -- and plays nothing; the ended text keeps its interval from that end.
        local revealOwner = cueOwner()
        DT:OnEncounterStart(nil, 3)
        DT:SetSpellShowAtOverride(CUE_WINDOW, 1)
        now = 300
        sendWarning(revealOwner, "warning")
        local lateReveal = cueJob(CUE_WINDOW)
        assert.equal(321, lateReveal.deadline)
        local soundsBefore = #soundCalls
        now = 323
        cueFire(lateReveal)
        assert.equal(0, #cueFrames(CUE_WINDOW))
        assert.equal(1, cueFrames(CUE_WINDOW .. "#ended")[1].frame.totalDuration)
        assert.equal(soundsBefore, #soundCalls)
        DT:OnEncounterEnd()

        -- Dispatched after the ended interval too (322 to 324): nothing at all.
        local goneOwner = cueOwner()
        DT:OnEncounterStart(nil, 3)
        now = 300
        sendWarning(goneOwner, "warning")
        local goneReveal = cueJob(CUE_WINDOW)
        now = 325
        cueFire(goneReveal)
        assert.equal(0, #cueFrames(CUE_WINDOW))
        assert.equal(0, #cueFrames(CUE_WINDOW .. "#ended"))
        assert.equal(soundsBefore, #soundCalls)
    end)

    it("a replacement, an owner teardown and a Timer cue's provider stop end the window with no ended text and remove one already showing, the stop leaving an older same-label row alone; a Timer cue's natural expiry shows the ended text for what is left of its interval, and a hidden one whose reveal and retire jobs are both overdue shows and sounds no expired bar whichever runs first, and nothing once the interval has passed; a pause after the end cannot move that interval and a pause before the end moves the end", function()
        local function showWindow(who)
            now = 100
            sendWarning(who, "warning")
            now = 102
            cueFire(cueJob(CUE_WINDOW))
        end
        local function runWindowOut(who)
            showWindow(who)
            now = 122
            cueTick(cueFrames(CUE_WINDOW)[1].frame)
        end
        -- The phase bar is published after a 30-second cooldown row that
        -- carries the same label and outlives it.
        local function showPhase(who)
            now = 100
            DT:EventCallback("BigWigs_Timer", who, 800, 30, nil, "Phase (1)", nil, nil, true, true)
            sendPhaseTimer(who, "Phase (1)")
        end
        -- The phase ends at 115; its expiry is processed one second late.
        local function runPhaseOut(who)
            showPhase(who)
            now = 116
            cueTick(cuePrimaryFrame(who, "Phase (1)"))
        end
        -- With a reveal of five seconds the bar stays hidden until 110 and
        -- has a reveal job (due 110) and a retire job (due 115). When both
        -- are overdue, either may be dispatched first.
        local function showHiddenPhase(who)
            DT:SetSpellShowAtOverride(CUE_PHASE, 5)
            showPhase(who)
        end
        local function fireHiddenJob(who, kind, at)
            local inst = State.FindCue(DT._state, who, CUE_PHASE, "Phase (1)")
            now = at
            for job in pairs(DT._jobs) do
                if job.kind == kind and job.instance == inst then
                    cueFire(job)
                    break
                end
            end
        end
        -- Whichever overdue job runs first ends the window: nothing of the
        -- expired bar is shown or sounded and its occurrence is retired.
        local function runHiddenPhaseOut(kind)
            return function(who)
                showHiddenPhase(who)
                local sounds = #soundCalls
                fireHiddenJob(who, kind, 116)
                assert.equal(sounds, #soundCalls, kind .. " first: no sound")
                assert.is_nil(State.FindCue(DT._state, who, CUE_PHASE, "Phase (1)"), kind .. " first: retired")
            end
        end
        local function stopPhase(who) DT:EventCallback("BigWigs_StopBar", who, "Phase (1)") end
        local function rowStillRuns(who, name)
            assert.equal("running", State.Find(DT._state, who, "Phase (1)").state, name .. ": older row")
        end
        local cases = {
            { name = "replacement", cueKey = CUE_WINDOW, live = showWindow, finish = runWindowOut, endedLeft = 2,
              interrupt = function(who) sendWarning(who, "again") end },
            { name = "owner teardown", cueKey = CUE_WINDOW, live = showWindow, finish = runWindowOut, endedLeft = 2,
              interrupt = function(who) DT:EventCallback("BigWigs_StopBars", who) end },
            { name = "provider stop", cueKey = CUE_PHASE, live = showPhase, finish = runPhaseOut, endedLeft = 1,
              interrupt = stopPhase, after = rowStillRuns },
            { name = "provider stop, hidden bar, retire job first", cueKey = CUE_PHASE, live = showHiddenPhase,
              finish = runHiddenPhaseOut("retire"), endedLeft = 1, interrupt = stopPhase, after = rowStillRuns },
            { name = "provider stop, hidden bar, overdue reveal first", cueKey = CUE_PHASE, live = showHiddenPhase,
              finish = runHiddenPhaseOut("reveal"), endedLeft = 1, interrupt = stopPhase, after = rowStillRuns },
        }
        for _, case in ipairs(cases) do
            local endedSlot = case.cueKey .. "#ended"

            local liveOwner = cueOwner()
            DT:OnEncounterStart(nil, 3)
            case.live(liveOwner)
            case.interrupt(liveOwner)
            assert.equal(0, #cueFrames(endedSlot), case.name .. ": interrupted while live")
            if case.after then case.after(liveOwner, case.name) end
            DT:OnEncounterEnd()

            local endedOwner = cueOwner()
            DT:OnEncounterStart(nil, 3)
            case.finish(endedOwner)
            assert.equal(1, #cueFrames(endedSlot), case.name .. ": natural end")
            assert.equal(case.endedLeft, cueFrames(endedSlot)[1].frame.totalDuration, case.name .. ": ended interval")
            case.interrupt(endedOwner)
            assert.equal(0, #cueFrames(endedSlot), case.name .. ": interrupted while the ended text shows")
            if case.after then case.after(endedOwner, case.name) end
            DT:OnEncounterEnd()
        end

        -- Either overdue job dispatched after the ended interval (115 to
        -- 117) draws and sounds nothing and still retires the occurrence.
        for _, kind in ipairs({ "retire", "reveal" }) do
            local lateOwner = cueOwner()
            DT:OnEncounterStart(nil, 3)
            showHiddenPhase(lateOwner)
            local sounds = #soundCalls
            fireHiddenJob(lateOwner, kind, 118)
            assert.equal(0, #cueFrames(CUE_PHASE .. "#ended"), kind .. " first, after the interval")
            assert.is_nil(State.FindCue(DT._state, lateOwner, CUE_PHASE, "Phase (1)"), kind .. " first, after the interval")
            assert.equal(sounds, #soundCalls, kind .. " first, after the interval")
            DT:OnEncounterEnd()
        end

        -- A pause that arrives after the window ran out, with neither job
        -- dispatched yet, ends the window from its own end (115) and never
        -- reaches its clock, so the resume four seconds later cannot move
        -- the ended interval: the result is the one expiry-first gives.
        for _, late in ipairs({ { at = 116, left = 1 }, { at = 118 } }) do
            local pauseOwner = cueOwner()
            DT:OnEncounterStart(nil, 3)
            showHiddenPhase(pauseOwner)
            local sounds = #soundCalls
            now = late.at
            DT:EventCallback("BigWigs_PauseBar", pauseOwner, "Phase (1)")
            assert.is_nil(State.FindCue(DT._state, pauseOwner, CUE_PHASE, "Phase (1)"), "pause at " .. late.at)
            now = late.at + 4
            DT:EventCallback("BigWigs_ResumeBar", pauseOwner, "Phase (1)")
            local ended = cueFrames(CUE_PHASE .. "#ended")
            if late.left then
                assert.equal(1, #ended, "pause at " .. late.at)
                assert.equal(late.left, ended[1].frame.totalDuration, "pause at " .. late.at)
                assert.equal(late.at, ended[1].frame._dtPresentation.clock.receivedAt, "pause at " .. late.at)
            else
                assert.equal(0, #ended, "pause at " .. late.at)
            end
            assert.equal(sounds, #soundCalls, "pause at " .. late.at)
            rowStillRuns(pauseOwner, "pause at " .. late.at)
            DT:OnEncounterEnd()
        end

        -- A pause before the end is honored: paused at 108 with seven
        -- seconds left and resumed at 120, the window ends at 127, and its
        -- retire job dispatched at 128 leaves one second of ended text.
        local earlyOwner = cueOwner()
        DT:OnEncounterStart(nil, 3)
        showHiddenPhase(earlyOwner)
        now = 108
        DT:EventCallback("BigWigs_PauseBar", earlyOwner, "Phase (1)")
        assert.equal("paused", State.FindCue(DT._state, earlyOwner, CUE_PHASE, "Phase (1)").state)
        now = 120
        DT:EventCallback("BigWigs_ResumeBar", earlyOwner, "Phase (1)")
        assert.equal(0, #cueFrames(CUE_PHASE .. "#ended"))
        fireHiddenJob(earlyOwner, "retire", 128)
        assert.equal(1, cueFrames(CUE_PHASE .. "#ended")[1].frame.totalDuration)
    end)

    it("the wanted aura list is empty when the module is off, the instance differs or sounds are muted, omits a disabled, unresolved or malformed rule, and yields five entries for a boss rule and one for a player rule", function()
        local registry = { { key = "Cue Dungeon", instanceID = 500 } }
        local data = {
            [3] = { dungeon = "Cue Dungeon", auraSounds = {
                { spellID = 11, trigger = "added", unit = "player", name = "Kept player rule", sound = "Alert" },
                { spellID = 12, trigger = "removed", unit = "boss", name = "Kept boss rule", sound = "Alert" },
                { spellID = 13, trigger = "added", unit = "player", name = "Disabled row", sound = "Alert" },
                { spellID = 14, trigger = "added", unit = "player", name = "Unresolved sound", sound = "Missing" },
                { spellID = 15, trigger = "stacked", unit = "player", name = "Unknown trigger", sound = "Alert" },
                { spellID = 16, trigger = "added", unit = "target", name = "Unknown unit", sound = "Alert" },
                { spellID = 17, trigger = "added", unit = "player", name = "Non-boolean disabled", sound = "Alert",
                  disabled = "true" },
                { spellID = 18, trigger = "added", unit = "player", name = "Unknown field", sound = "Alert",
                  volume = 1 },
                { spellID = 19, trigger = "added", unit = "player", sound = "Alert" },
                { spellID = 20, trigger = "added", unit = "player", name = "Missing sound" },
                { spellID = "22", trigger = "added", unit = "player", name = "Text spell ID", sound = "Alert" },
                "not a rule",
            } },
            [4] = { dungeon = "Other Dungeon", auraSounds = {
                { spellID = 21, trigger = "added", unit = "player", name = "Other dungeon", sound = "Alert" },
            } },
        }
        local function context(extra)
            local ctx = {
                enabled = true, instanceID = 500, muted = false, channel = "SFX",
                triggers = { added = "Added", removed = "Removed" },
                isDisabled = function(key) return key == "aura:3:13:added" end,
                soundFor = function(key) return key == "aura:3:14:added" and "Missing" or "Alert" end,
                resolveMedia = function(name) return name == "Alert" and "path/Alert.ogg" or nil end,
            }
            for k, v in pairs(extra) do ctx[k] = v end
            return ctx
        end

        local empties = {
            { name = "module off", extra = { enabled = false } },
            { name = "another instance", extra = { instanceID = 501 } },
            { name = "preset sounds muted", extra = { muted = true } },
        }
        for _, case in ipairs(empties) do
            assert.same({}, DT._BuildAuraSoundWanted(data, registry, context(case.extra)), case.name)
        end

        local wanted = DT._BuildAuraSoundWanted(data, registry, context({}))
        assert.equal(6, #wanted)
        local byToken = {}
        for _, entry in ipairs(wanted) do
            byToken[entry.spellID .. ":" .. entry.unitToken] = entry
        end
        assert.same({ trigger = "Added", unitToken = "player", spellID = 11, path = "path/Alert.ogg", channel = "SFX" },
            byToken["11:player"])
        for n = 1, 5 do
            assert.same({ trigger = "Removed", unitToken = "boss" .. n, spellID = 12,
                          path = "path/Alert.ogg", channel = "SFX" }, byToken["12:boss" .. n])
        end
    end)

    local function stackTriggers(triggers)
        local registry = { { key = "Stack Dungeon", instanceID = 600 } }
        local data = {
            [5] = { dungeon = "Stack Dungeon", auraSounds = {
                { spellID = 31, trigger = "added", unit = "player", name = "Gained", sound = "Alert" },
                { spellID = 31, trigger = "increased", unit = "player", name = "Stack gained", sound = "Alert" },
            } },
        }
        local wanted = DT._BuildAuraSoundWanted(data, registry, {
            enabled = true, instanceID = 600, muted = false, channel = "SFX", triggers = triggers,
            isDisabled = function() return false end,
            soundFor = function() return "Alert" end,
            resolveMedia = function() return "path/Alert.ogg" end,
        })
        local list = {}
        for _, entry in ipairs(wanted) do list[#list + 1] = entry.trigger end
        return list
    end

    it("an increased aura rule yields its own entry with the increased client trigger beside an added rule for the same aura", function()
        assert.same({ "Added", "ApplicationsIncreased" },
            stackTriggers({ added = "Added", removed = "Removed", increased = "ApplicationsIncreased" }))
    end)

    it("an increased aura rule is omitted when the client has no increased trigger", function()
        assert.same({ "Added" }, stackTriggers({ added = "Added", removed = "Removed" }))
    end)

    -- Deadline 10, extension 3: showAtSeconds 1 floors to 3.15, so the reveal
    -- (9.85) is still pending at 9.5 and the retire job sits at 13.
    local function addStageRow(data, contract)
        data[2].spells[710] = { name = "Stage Row", castType = "begincast", castDuration = 3,
            showAtSeconds = 1, sound = "Alert",
            timerSource = contract({ canceledStop = { stage = 3, within = 1 } }) }
    end

    it("a concurrent short restart is silently retired in either callback order without losing the real cast or a long forecast", function()
        for _, timerFirst in ipairs({ true, false }) do
            local m = loadTimelineModule({ encounterData = function(data, contract)
                data[2].spells[713] = { name = "Restart Row", castDuration = 3,
                    showAtSeconds = 0, sound = "Alert", soundOnHide = "Alert",
                    timerSource = contract({ suppressConcurrentRestart = { from = 29, duration = 6 } }) }
            end })
            _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
            local current = m.publish(713, "Current", 29, 71, 6)
            m.clock.now = 29
            local future = m.publish(713, "Ordinary replacement", 29, 73, 6)
            local before = #soundCalls
            local target, frame, revealHandle
            local function publishShort()
                m.DT:EventCallback("BigWigs_StartBar", m.owner, 713, "Extra", 6, nil, true, nil, nil, 72)
                target, frame = m.publish(713, "Extra", 6, 72, 6)
                if frame then
                    assert.is_false(frame:IsShown())
                    revealHandle = frame._dtPresentation.revealJob.handle
                end
            end
            if timerFirst then publishShort() end
            m.DT:EventCallback("BigWigs_StopBar", m.owner, "Current")
            if not timerFirst then publishShort() end
            assert.is_nil((m.find("Extra")))
            assert.equal(current, (m.find("Current")))
            assert.equal(29, current.anchorElapsed)
            assert.equal(future, (m.find("Ordinary replacement")))
            assert.equal(before, #soundCalls)
            if target then
                assert.equal("retired", target.state)
                assert.is_nil(m.DT._presentations[target])
                assert.is_true(revealHandle.canceled)
                m.clock.now = 29.2
                revealHandle.fn(revealHandle.arg)
                assert.equal(before, #soundCalls)
            end
            m.DT:EventCallback("BigWigs_StopBar", m.owner, "Extra")
            assert.equal(current, (m.find("Current")))
            m.DT:EventCallback("BigWigs_StopBars", m.owner)
            m.clock.now = 29.3
            m.DT:EventCallback("BigWigs_StartBar", m.owner, 713, "Fresh pull", 6, nil, true, nil, nil, 74)
            local opening = m.publish(713, "Fresh pull", 6, 74, 6)
            assert.is_truthy(opening)
        end
    end)

    it("six-second repeats and replacements without distinct confirmed identities remain eligible and keep their original end", function()
        local cases = {
            { name = "normal six-to-six", duration = 6, state = 2, identity = true },
            { name = "canceled source", duration = 29, state = 3, identity = true },
            { name = "target identity absent", duration = 29, state = 2 },
            { name = "source state absent", duration = 29, state = 0, identity = true },
            { name = "own Finished before reveal", duration = 29, state = 0, identity = true, ownFinished = true },
        }
        for _, case in ipairs(cases) do
            local m = loadTimelineModule({ encounterData = function(data, contract)
                data[2].spells[713] = { name = "Restart Row", castDuration = 3,
                    showAtSeconds = 0, sound = "Alert",
                    timerSource = contract({ suppressConcurrentRestart = { from = 29, duration = 6 } }) }
            end })
            _G.C_EncounterTimeline = { GetEventState = function() return case.state end }
            m.publish(713, "Current", case.duration, 71, 6)
            m.clock.now = case.duration
            if case.identity then
                m.DT:EventCallback("BigWigs_StartBar", m.owner, 713, "Next", 6, nil, true, nil, nil, 72)
            end
            local target, frame = m.publish(713, "Next", 6, 72, 6)
            m.DT:EventCallback("BigWigs_StopBar", m.owner, "Current")
            assert.equal(target, (m.find("Next")), case.name)
            local record = frame._dtPresentation
            assert.near(0.16, record.revealJob.deadline, 0.00001)
            assert.equal(9, record.retireJob.deadline)
            local before = #soundCalls
            if case.ownFinished then
                m.clock.now = case.duration + 0.1
                _G.C_EncounterTimeline.GetEventState = function() return 2 end
                m.DT:EventCallback("BigWigs_StopBar", m.owner, "Next")
                assert.near(3.1, record.retireJob.deadline, 0.00001)
            else
                m.clock.now = case.duration + 0.2
                record.revealJob.handle.fn(record.revealJob.handle.arg)
            end
            assert.is_true(frame:IsShown())
            assert.equal(before + 1, #soundCalls)
        end
    end)

    local function auraRetryFixture()
        local m = loadTimelineModule()
        require("dev.spec._helpers").loadModule("Modules/AuraTracking/AuraEngine/Sound.lua", m.KE)
        m.hidden, m.added, m.removed, m.deferred = false, {}, {}, {}
        m.KE.DungeonTimerDungeons = { { key = "Explicit Dungeon", instanceID = 42 } }
        m.KE.EncounterData[2].auraSounds = {
            { spellID = 801, trigger = "added", unit = "player", name = "Reminder", sound = "Alert" },
            { spellID = 802, trigger = "added", unit = "player", name = "Other", sound = "Alert", disabled = true },
        }
        m.key = m.DT.MakeAuraKey(2, 801, "added")
        m.other = m.DT.MakeAuraKey(2, 802, "added")
        m.KE.AreAuraIdentitiesHidden = function() return m.hidden end
        _G.GetInstanceInfo = function() return nil, nil, nil, nil, nil, nil, nil, 42 end
        _G.C_Timer = { After = function(_, fn) m.deferred[#m.deferred + 1] = fn end }
        _G.C_UnitAuras = {
            AddAuraSound = function(_, rule)
                m.added[#m.added + 1] = rule
                return #m.added
            end,
            RemoveAuraSound = function(id) m.removed[#m.removed + 1] = id end,
        }
        return m
    end

    it("aura retry listeners are absent for both fresh silence and registered sounds muted afterward", function()
        local m = auraRetryFixture()
        m.DT:SetSpellSoundOnShow(m.key, "None")
        assert.is_nil(m.DT._auraSounds)
        assert.is_false(m.DT._auraSoundEvents == true)
        m.DT:SetSpellSoundOnShow(m.key, nil)
        assert.equal(1, #m.added)
        m.DT:SetSpellSoundOnShow(m.key, "None")
        assert.same({ 1 }, m.removed)
        assert.is_nil(m.DT._auraSounds)
        assert.is_false(m.DT._auraSoundEvents == true)
        for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED" }) do
            assert.equal(0, m.events.count(m.events.registered, event))
        end
    end)

    it("aura retries preserve standing registrations and detach listeners after restricted additions succeed", function()
        local m = auraRetryFixture()
        m.DT:SyncAuraSounds()
        assert.equal(1, #m.added)
        m.hidden = true
        m.DT:SetSpellDisabled(m.other, false)
        assert.equal(1, #m.added)
        assert.is_true(m.DT._auraSoundEvents)
        assert.is_true(m.DT._auraSounds:IsPending())
        m.DT:OnAuraSoundRestrictionChanged()
        assert.equal(1, #m.deferred)
        m.hidden = false
        m.deferred[1]()
        assert.equal(2, #m.added)
        assert.equal(0, #m.removed)
        assert.is_false(m.DT._auraSounds:IsPending())
        assert.is_false(m.DT._auraSoundEvents)
        for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED" }) do
            assert.equal(1, m.events.count(m.events.registered, event))
            assert.equal(1, m.events.count(m.events.unregistered, event))
        end
    end)

    it("disabling aura reminders cancels a queued retry without recreating native registrations", function()
        local m = auraRetryFixture()
        m.hidden = true
        m.DT:SyncAuraSounds()
        assert.is_true(m.DT._auraSoundEvents)
        m.DT:OnAuraSoundRestrictionChanged()
        assert.equal(1, #m.deferred)
        m.DT:OnDisable()
        m.hidden = false
        m.deferred[1]()
        assert.equal(0, #m.added)
        assert.is_nil(m.DT._auraSounds)
        assert.is_false(m.DT._auraSoundEvents)
    end)

    local function providerSetupFixture()
        local m = loadTimelineModule()
        local queue, prompts, closed, flags, disabled = {}, {}, {}, {}, {}
        local fixture = { DT = m.DT, KE = m.KE, queue = queue, prompts = prompts, closed = closed,
            flags = flags, disabled = disabled, instance = 2859, profile = "original" }
        _G.C_Timer = { After = function(_, fn) queue[#queue + 1] = fn end }
        _G.GetInstanceInfo = function() return nil, nil, fixture.difficulty, nil, nil, nil, nil, fixture.instance end
        _G.InCombatLockdown = function() return false end
        m.DT._providerSetupQueued = false
        m.DT.IsSpellDisabled = function(_, key) return disabled[key] == true end
        m.DT._ReadCueProviderOption = function(_, key)
            local value = flags[key] or 0
            return m.State.ProviderMessageStatus(value, 1, 2), {
                profile = fixture.profile, flags = value, toggles = flags, messageBit = 1, emphasizeBit = 2,
            }, { optionKey = key, label = key }
        end
        m.KE.CreatePrompt = function(_, ...)
            local args = { ... }
            prompts[#prompts + 1] = { label = args[1], accept = args[10], decline = args[11] }
        end
        m.KE.ClosePromptIfOwner = function(_, accept) closed[#closed + 1] = accept end
        function fixture.flush()
            local count = 0
            while #queue > 0 do
                count = count + 1
                assert.is_true(count < 20, "setup callbacks must settle")
                table.remove(queue, 1)()
            end
        end
        m.DT:_RequestProviderSetupCheck()
        fixture.flush()
        return fixture
    end

    it("Whelps setup follows the current dungeon difficulty while allowing advance setup outside Ruby", function()
        local whelps = "cue:2609:awaken_whelps"
        local cases = {
            { difficulty = 1 }, { difficulty = 2 }, { difficulty = nil },
            { difficulty = { __secret = true } },
            { difficulty = 8, applicable = true }, { difficulty = 23, applicable = true },
        }
        for _, case in ipairs(cases) do
            local m = providerSetupFixture()
            m.instance, m.difficulty = 2521, case.difficulty
            m.DT:_RequestProviderSetupCheck()
            m.flush()
            if case.applicable then
                assert.equal(whelps, m.DT._cueProviderKey)
                assert.equal("missing", m.DT:_GetProviderSetupNotice(whelps))
            else
                assert.is_nil(m.DT._cueProviderKey)
                assert.equal("not-applicable", m.DT:_GetProviderSetupNotice(whelps))
                m.DT:_OpenCueProviderPrompt(whelps, "explicit")
                assert.is_nil(m.DT._cueProviderKey)
            end
            m.instance = 0
            m.DT:_RequestProviderSetupCheck()
            m.flush()
            m.DT:_OpenCueProviderPrompt(whelps, "explicit")
            assert.equal(whelps, m.DT._cueProviderKey)
        end
    end)

    it("Whelps acceptance rechecks difficulty and cannot enable a message after leaving its supported mode", function()
        local m = providerSetupFixture()
        local whelps = "cue:2609:awaken_whelps"
        m.instance, m.difficulty = 2521, 8
        m.DT:_RequestProviderSetupCheck()
        m.flush()
        assert.equal(whelps, m.DT._cueProviderKey)
        local accept = m.DT._cueProviderAccept
        m.difficulty = 2
        accept()
        m.flush()
        assert.is_nil(m.flags[whelps])
        assert.is_nil(m.DT._cueProviderKey)
    end)

    it("provider checks attribute each failed addon once per click while preserving every cue check and later attempts", function()
        for _, case in ipairs({
            { name = "core", core = true, failures = { "BigWigs_Core" } },
            { name = "content", failures = { "LittleWigs", "LittleWigs_Dragonflight" } },
        }) do
            local m = providerSetupFixture()
            local reports, reads = {}, {}
            local bear, haranir, whelps = "cue:3201:bear_form", "cue:3201:haranir_form", "cue:2609:awaken_whelps"
            m.KE.Print = function(_, message) reports[#reports + 1] = message end
            m.DT._ReadCueProviderOption = function(_, key)
                reads[key] = (reads[key] or 0) + 1
                return "unreadable", nil, nil, "not-loaded"
            end
            if case.core then _G.BigWigs = nil else _G.BigWigs = {} end
            _G.C_AddOns = {
                IsAddOnLoaded = function() return false, false end,
                LoadAddOn = function() return false, "DISABLED" end,
            }
            local click = {}
            m.DT:_CheckProviderSetupNow(bear, click)
            m.DT:_CheckProviderSetupNow(haranir, click)
            m.DT:_CheckProviderSetupNow(whelps, click)
            assert.equal(#case.failures, #reports, case.name)
            for i, addon in ipairs(case.failures) do
                assert.is_truthy(reports[i]:find(addon, 1, true), case.name)
                assert.is_truthy(reports[i]:find("DISABLED", 1, true), case.name)
            end
            for _, key in ipairs({ bear, haranir, whelps }) do assert.equal(2, reads[key], case.name) end
            m.DT:_CheckProviderSetupNow(bear, {})
            assert.equal(#case.failures + 1, #reports, case.name)
            m.DT:_CheckProviderSetupNow(haranir)
            assert.equal(#case.failures + 2, #reports, case.name)
        end
    end)

    it("provider setup advances after acceptance and Later while unrelated disabled or satisfied cues leave its prompt alone", function()
        local m = providerSetupFixture()
        local bear, haranir = "cue:3201:bear_form", "cue:3201:haranir_form"
        local first = m.prompts[1]
        assert.equal(bear, first.label)
        m.disabled[haranir] = true
        m.DT:_OnProviderCueChanged(haranir)
        m.flush()
        assert.equal(first.accept, m.DT._cueProviderAccept)
        assert.equal(0, #m.closed)
        m.disabled[haranir] = false
        first.accept()
        m.flush()
        assert.equal(1, m.flags[bear])
        assert.equal(haranir, m.prompts[2].label)
        first.accept()
        m.prompts[2].decline()
        m.flush()
        assert.equal(2, #m.prompts)
        assert.is_nil(m.flags[haranir])
        assert.is_nil(m.DT._cueProviderAccept)
    end)

    it("provider setup advances after Later, resets on leaving the dungeon, and retires only the disabled prompt's cue", function()
        local m = providerSetupFixture()
        local bear = "cue:3201:bear_form"
        local haranir = "cue:3201:haranir_form"
        m.prompts[1].decline()
        m.flush()
        assert.equal(haranir, m.prompts[2].label)
        m.instance = 0
        m.DT:_RequestProviderSetupCheck()
        m.flush()
        assert.is_nil(m.DT._cueProviderAccept)
        assert.is_nil(m.DT._providerSetupAnswered[bear])
        m.instance = 2859
        m.DT:_RequestProviderSetupCheck()
        m.flush()
        assert.equal(bear, m.prompts[3].label)
        m.disabled[bear] = true
        m.DT:_OnProviderCueChanged(bear)
        m.flush()
        assert.equal(haranir, m.prompts[4].label)
    end)

    it("an explicit provider request can replace another cue and stale or profile-changed acceptance never writes", function()
        local m = providerSetupFixture()
        local first = m.prompts[1]
        local light = "cue:3101:light_infusion"
        m.DT:_OpenCueProviderPrompt(light, "explicit")
        assert.equal(first.accept, m.closed[1])
        local second = m.prompts[2]
        m.DT:_RequestProviderSetupCheck()
        m.flush()
        assert.equal(second.accept, m.DT._cueProviderAccept)
        first.accept()
        assert.is_nil(next(m.flags))
        m.profile = "changed"
        second.accept()
        assert.is_nil(next(m.flags))
        m.DT:_OpenCueProviderPrompt(light, "explicit")
        local third = m.prompts[3]
        assert.equal(third.accept, m.DT._cueProviderAccept)
        m.DT:OnProviderSetupSignal("BigWigs_ProfileUpdate")
        assert.equal(third.accept, m.closed[2])
        assert.is_nil(m.DT._cueProviderAccept)
        third.accept()
        assert.is_nil(next(m.flags))
    end)

    it("refuses a repeated live overlap label before replacing its countdown or waking its successor", function()
        local m = loadTimelineModule({ encounterData = function(data, contract)
            data[2].spells[701].timerSource = contract({ holdOverlapping = true })
        end })
        _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
        local current, frame = m.publish(701, "Overlap (1)", 10, 81, 6)
        m.clock.now = 10
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Overlap (1)")
        m.clock.now = 10.1
        local nextInst, nextFrame = m.publish(701, "Overlap (2)", 1, 82, 6)
        local nextRecord = nextFrame._dtPresentation
        assert.is_true(nextRecord.overlapHeld)
        local before = #soundCalls
        local labels = m.DT._state.awaitingStop[m.owner].labels
        assert.is_nil(labels["Overlap (1)"])
        m.clock.now = 10.2
        m.publish(701, "Overlap (1)", 20)
        local kept, keptFrame = m.find("Overlap (1)")
        assert.equal(current, kept)
        assert.equal(frame, keptFrame)
        assert.equal(current, (m.State.FindPublished(m.DT._state, m.owner, "Overlap (1)")))
        assert.is_nil(labels["Overlap (1)"])
        assert.equal(nextInst, (m.find("Overlap (2)")))
        assert.is_true(nextRecord.overlapHeld)
        assert.is_false(nextFrame:IsShown())
        assert.equal(before, #soundCalls)
    end)

    it("silently releases hidden overlap work when its clock sample refuses", function()
        local m = loadTimelineModule({ encounterData = function(data, contract)
            data[2].spells[701].timerSource = contract({ holdOverlapping = true })
        end })
        _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
        local current = m.publish(701, "Overlap (1)", 10, 81, 6)
        m.clock.now = 10
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Overlap (1)")
        m.clock.now = 10.1
        local hidden, frame = m.publish(701, "Overlap (2)", 1, 82, 6)
        local record = frame._dtPresentation
        assert.is_true(record.overlapHeld)
        local callback = record.retireJob.handle
        local before = #soundCalls
        m.State.Sample(hidden, 12)
        m.clock.now = 11
        callback.fn(callback.arg)
        assert.equal("retired", hidden.state)
        assert.is_nil(m.DT._presentations[hidden])
        assert.is_nil(record.retireJob)
        for job in pairs(m.DT._jobs) do assert.are_not.equal(hidden, job.instance) end
        assert.equal(current, (m.find("Overlap (1)")))
        assert.equal(before, #soundCalls)
    end)

    it("two Finished stops anchor the current occurrence but preserve a fresh future forecast and its ordinary sounds", function()
        local m = loadTimelineModule({ encounterData = function(data, contract)
            data[2].spells[712] = { name = "Future Row", castDuration = 3,
                showAtSeconds = 5, sound = "Alert", soundOnHide = "Alert",
                timerSource = contract({ retainEarlyFinished = true }) }
        end })
        _G.C_EncounterTimeline = { GetEventState = function() return 2 end }
        local current = m.publish(712, "Future Row (1)", 8, 71, 6)
        m.clock.now = 8
        local future, frame = m.publish(712, "Future Row (2)", 45, 72, 6)
        local record = frame._dtPresentation
        local reveal, retire = record.revealJob, record.retireJob
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Future Row (1)")
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Future Row (2)")
        assert.equal(8, current.anchorElapsed)
        assert.is_nil(future.anchorElapsed)
        assert.equal("finished", future.retainedEstimate)
        assert.equal(reveal, record.revealJob)
        assert.equal(retire, record.retireJob)
        assert.equal(43, reveal.deadline)
        assert.equal(48, retire.deadline)
        m.clock.now = 51
        local soundsBefore = #soundCalls
        reveal.handle.fn(reveal.handle.arg)
        assert.equal(soundsBefore + 1, #soundCalls)
        m.clock.now = 56
        retire.handle.fn(retire.handle.arg)
        m.tick(frame)
        assert.equal("retired", future.state)
        assert.equal(soundsBefore + 2, #soundCalls)
    end)

    it("the StopBar route keeps an in-stage Canceled stop to its original end with a silent pending reveal and no anchor, and retires a row published before the stage", function()
        local cases = {
            { name = "published in stage 3", publishStage = 3, stop = 9.5, kept = true },
            { name = "just past deadline", publishStage = 3, stop = 10.009, kept = true },
            { name = "published in stage 2, stopped in stage 3", publishStage = 2, stop = 9.5, kept = false },
        }
        for _, case in ipairs(cases) do
            local m = loadTimelineModule({ encounterData = addStageRow })
            local stage = case.publishStage
            m.owner.GetStage = function() return stage end
            _G.C_EncounterTimeline = { GetEventState = function() return 3 end }  -- Canceled
            m.clock.now = 0
            local inst, frame = m.publish(710, "Stage Row (1)", 10, 51, 6)
            local record = frame._dtPresentation
            stage = 3
            m.clock.now = case.stop
            m.DT:EventCallback("BigWigs_StopBar", m.owner, "Stage Row (1)")
            if case.kept then
                assert.equal(inst, (m.find("Stage Row (1)")), case.name)
                assert.equal("canceled", inst.retainedEstimate, case.name)
                assert.is_nil(inst.anchorElapsed, case.name)
                assert.is_true(record.suppressShowSound, case.name)
                assert.equal(13, record.retireJob.deadline, case.name)
            else
                assert.is_nil((m.find("Stage Row (1)")), case.name)
            end
        end
    end)

    it("an owner StopBars retires a retained canceled estimate and cancels its pending jobs", function()
        local m = loadTimelineModule({ encounterData = addStageRow })
        m.owner.GetStage = function() return 3 end
        _G.C_EncounterTimeline = { GetEventState = function() return 3 end }  -- Canceled
        m.clock.now = 0
        local inst, frame = m.publish(710, "Stage Row (1)", 10, 51, 6)
        local record = frame._dtPresentation
        local revealHandle, retireHandle = record.revealJob.handle, record.retireJob.handle
        m.clock.now = 9.5
        m.DT:EventCallback("BigWigs_StopBar", m.owner, "Stage Row (1)")
        assert.equal("canceled", inst.retainedEstimate)
        m.DT:EventCallback("BigWigs_StopBars", m.owner)
        assert.equal("retired", inst.state)
        assert.is_nil(m.DT._presentations[inst])
        assert.is_true(revealHandle.canceled)
        assert.is_true(retireHandle.canceled)
    end)

    it("a shown retained canceled estimate ends without its hide sound, while the same row anchored by Finished plays it", function()
        local cases = {
            { name = "retained", state = 3, endAt = 13, hideSounds = 0 },
            { name = "anchored", state = 2, endAt = 12.5, hideSounds = 1 },
        }
        for _, case in ipairs(cases) do
            local m = loadTimelineModule({ encounterData = function(data, contract)
                data[2].spells[711] = { name = "Shown Stage Row", castType = "begincast", castDuration = 3,
                    showAtSeconds = 0, soundOnHide = "Alert",
                    timerSource = contract({ canceledStop = { stage = 3, within = 1 } }) }
            end })
            m.owner.GetStage = function() return 3 end
            _G.C_EncounterTimeline = { GetEventState = function() return case.state end }
            m.clock.now = 0
            local inst, frame = m.publish(711, "Shown Stage Row (1)", 10, 61, 6)
            m.clock.now = 9.5
            m.DT:EventCallback("BigWigs_StopBar", m.owner, "Shown Stage Row (1)")
            local before = #soundCalls
            m.clock.now = case.endAt
            m.tick(frame)
            assert.equal("retired", inst.state, case.name)
            assert.equal(case.hideSounds, #soundCalls - before, case.name)
        end
    end)

    it("_ReadProviderStage returns the owner's plain finite stage", function()
        local m = loadTimelineModule()
        for _, stage in ipairs({ 3, 1.5 }) do
            assert.equal(stage, m.DT._ReadProviderStage({ GetStage = function() return stage end }))
        end
    end)

    it("_ReadProviderStage refuses a missing or secret owner or member, a raising call and a non-number or non-finite stage", function()
        local m = loadTimelineModule()
        local secret = { __secret = true }
        local cases = {
            { name = "nil owner", owner = nil },
            { name = "secret owner", owner = secret },
            { name = "no member", owner = {} },
            { name = "number member", owner = { GetStage = 3 } },
            { name = "secret member", owner = { GetStage = secret } },
            { name = "raising call", owner = { GetStage = function() error("stage read failed") end } },
            { name = "string stage", owner = { GetStage = function() return "3" end } },
            { name = "NaN stage", owner = { GetStage = function() return 0 / 0 end } },
            { name = "infinite stage", owner = { GetStage = function() return math.huge end } },
        }
        for _, case in ipairs(cases) do
            local value, reason = m.DT._ReadProviderStage(case.owner)
            assert.is_nil(value, case.name)
            assert.equal("string", type(reason), case.name)
        end
    end)
    local function replacementModule()
        local h = loadTimelineModule({ encounterData = function(data, contract)
            data[2].spells[701].timerSource = contract({ replacement = { from = 65, duration = 3 } })
        end })
        local states = { [1] = 0, [2] = 0 }
        _G.C_EncounterTimeline = { GetEventState = function(id) return states[id] end }
        local function publish(id, duration)
            h.DT:OnEncounterTimelineEventAdded(nil, { source = 0, id = id, duration = duration, maxQueueDuration = 6 })
            h.DT:EventCallback("BigWigs_StartBar", h.owner, 701, "Ritual (2)", duration, nil, true, nil, nil, id)
            h.DT:EventCallback("BigWigs_Timer", h.owner, 701, duration, nil, "Ritual (2)", nil, nil, true, true)
            return h.find("Ritual (2)")
        end
        return h, states, publish
    end

    it("hands a canceled forecast to its exact replacement in either callback order", function()
        for _, replacementFirst in ipairs({ true, false }) do
            local h, states, publish = replacementModule()
            local predecessor = publish(1, 65)
            h.clock.now = 62
            states[1] = 3
            if replacementFirst then
                publish(2, 3)
                assert.equal(predecessor, h.find("Ritual (2)"))
                h.clock.now = 62.1
            end
            h.DT:EventCallback("BigWigs_StopBar", h.owner, "Ritual (2)")
            if not replacementFirst then publish(2, 3) end
            local replacement = h.find("Ritual (2)")
            assert.is_not_nil(replacement)
            assert.are_not.equal(predecessor, replacement)
            assert.equal("retired", predecessor.state)
            assert.equal(62, replacement.sourceClock.receivedAt)
            assert.equal(2, replacement.timelineIdentity)
            h.clock.now = 65
            states[2] = 2
            h.DT:EventCallback("BigWigs_StopBar", h.owner, "Ritual (2)")
            assert.equal(3, replacement.anchorElapsed)
            local elapsed = h.State.Sample(replacement, h.clock.now)
            assert.equal(3, h.State.AnchoredRemaining(replacement, elapsed))
        end
    end)

    it("refuses held replacement work after native-state or correlation refusal and upstream teardown", function()
        for _, case in ipairs({
            { name = "canceled", state = 3 },
            { name = "finished", state = 2 },
            { name = "paused", state = 1 },
            { name = "missing", state = false },
            { name = "declared secret", state = { __secret = true } },
            { name = "no record", edit = function(h) h.DT._state.timelineEvents[2][62] = nil end },
            { name = "mismatched record", edit = function(h) h.DT._state.timelineEvents[2][62][1].id = 9 end },
            -- These refuse before the replay predicate; they exercise its callers' cleanup.
            { name = "no api", edit = function() _G.C_EncounterTimeline = nil end },
            { name = "disabled module", edit = function(h) h.DT:OnDisable() end },
        }) do
            local h, states, publish = replacementModule()
            publish(1, 65)
            h.clock.now = 62
            publish(2, 3)
            states[1] = 3
            if case.state == false then states[2] = nil
            elseif case.state ~= nil then states[2] = case.state end
            if case.edit then case.edit(h) end
            h.DT:EventCallback("BigWigs_StopBar", h.owner, "Ritual (2)")
            assert.is_nil(h.find("Ritual (2)"), case.name)
        end
    end)

end)

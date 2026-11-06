-- Tier 2: Core/Conflicts.lua. The decision layer is pure -- given a profile
-- snapshot, a loaded-addon predicate and the ElvUI-skinning flag, it returns
-- the prompts to raise. The REAL file loads headless via L.loadConflicts().
local L = require("dev.spec._ke_loader")

-- Builds an env for the decision layer. Defaults: SkinTooltips enabled,
-- nothing loaded, ElvUI not owning skinning.
local function env(opts)
    opts = opts or {}
    local loaded = opts.loaded or {}
    return {
        profile = opts.profile or { Skinning = { Tooltips = { Enabled = true } } },
        isLoaded = function(name) return loaded[name] == true end,
        shouldNotLoad = opts.shouldNotLoad or false,
    }
end

describe("Core/Conflicts.lua decision layer", function()
    local KE
    before_each(function()
        KE = L.loadConflicts()
    end)

    describe("KE:BuildConflictQueue", function()
        it("returns an empty queue when no rival addon is loaded", function()
            assert.same({}, KE:BuildConflictQueue(env()))
        end)

        it("queues one prompt when a rival is loaded and the module is on", function()
            local queue = KE:BuildConflictQueue(env({ loaded = { TipTac = true } }))
            assert.equals(1, #queue)
            assert.equals("TipTac", queue[1].source)
            assert.equals("SkinTooltips", queue[1].module)
            assert.equals("Tooltip", queue[1].label)
        end)

        it("queues nothing when the module is disabled", function()
            local queue = KE:BuildConflictQueue(env({
                loaded = { TipTac = true },
                profile = { Skinning = { Tooltips = { Enabled = false } } },
            }))
            assert.same({}, queue)
        end)

        -- Regression guard for deviation 2. The saved Enabled flag stays true
        -- while ElvUI holds the module inert, so testing the flag alone would
        -- prompt about a conflict that is not happening.
        it("queues nothing for a skinGated entry when ElvUI owns skinning", function()
            local queue = KE:BuildConflictQueue(env({
                loaded = { TipTac = true },
                shouldNotLoad = true,
            }))
            assert.same({}, queue)
        end)

        it("queues one prompt per loaded rival, in registry order", function()
            local queue = KE:BuildConflictQueue(env({
                loaded = { TipTac = true, TacoTip = true },
            }))
            assert.equals(2, #queue)
            assert.equals("TipTac", queue[1].source)
            assert.equals("TacoTip", queue[2].source)
        end)

        it("skips an entry whose dbPath does not resolve, without erroring", function()
            local queue = KE:BuildConflictQueue(env({
                loaded = { TipTac = true },
                profile = {},
            }))
            assert.same({}, queue)
        end)

        it("queues a prompt for EllesmereUIChat when the Chat module is on", function()
            local queue = KE:BuildConflictQueue({
                profile = { Skinning = { Chat = { Enabled = true } } },
                isLoaded = function(name) return name == "EllesmereUIChat" end,
                shouldNotLoad = false,
            })
            assert.equals(1, #queue)
            assert.equals("EllesmereUIChat", queue[1].source)
            assert.equals("Chat", queue[1].module)
            assert.equals("Chat", queue[1].label)
        end)

        it("queues nothing for a chat rival when the Chat module is off", function()
            local queue = KE:BuildConflictQueue({
                profile = { Skinning = { Chat = { Enabled = false } } },
                isLoaded = function(name) return name == "Prat-3.0" end,
                shouldNotLoad = false,
            })
            assert.same({}, queue)
        end)

        it("skips the skin-gated Chat entry when ElvUI owns skinning", function()
            local queue = KE:BuildConflictQueue({
                profile = { Skinning = { Chat = { Enabled = true } } },
                isLoaded = function(name) return name == "Chatter" end,
                shouldNotLoad = true,
            })
            assert.same({}, queue)
        end)
    end)

    describe("KE:GetModuleConflict", function()
        it("names the rival when the module is off and a rival is loaded", function()
            local rival = KE:GetModuleConflict("SkinTooltips", env({
                loaded = { TipTac = true },
                profile = { Skinning = { Tooltips = { Enabled = false } } },
            }))
            assert.equals("TipTac", rival)
        end)

        it("returns nil while the module is still on", function()
            assert.is_nil(KE:GetModuleConflict("SkinTooltips", env({
                loaded = { TipTac = true },
            })))
        end)

        it("returns nil when the module is off but no rival is loaded", function()
            assert.is_nil(KE:GetModuleConflict("SkinTooltips", env({
                profile = { Skinning = { Tooltips = { Enabled = false } } },
            })))
        end)

        -- An unreadable DB means UNKNOWN, not off. Without the `not moduleDB`
        -- half of the guard this reports a conflict for a module whose state
        -- could not be read.
        it("returns nil when the module's DB cannot be read", function()
            assert.is_nil(KE:GetModuleConflict("SkinTooltips", env({
                loaded = { TipTac = true },
                profile = {},
            })))
        end)

        it("returns nil for a skinGated entry when ElvUI owns skinning", function()
            assert.is_nil(KE:GetModuleConflict("SkinTooltips", env({
                loaded = { TipTac = true },
                profile = { Skinning = { Tooltips = { Enabled = false } } },
                shouldNotLoad = true,
            })))
        end)
    end)

    describe("LFGReminder conflict entry", function()
        it("queues one entry when LFGReminder is enabled and EllesmereUIQoL is loaded", function()
            local queue = KE:BuildConflictQueue({
                profile = { LFGReminder = { Enabled = true } },
                isLoaded = function(name) return name == "EllesmereUIQoL" end,
                shouldNotLoad = false,
            })
            assert.equals(1, #queue)
            assert.equals("LFGReminder", queue[1].module)
        end)

        -- Regression guard: this row is deliberately NOT skinGated, so a
        -- copied-from-SkinTooltips row would wrongly clear this queue.
        it("still queues the entry when ElvUI owns skinning", function()
            local queue = KE:BuildConflictQueue({
                profile = { LFGReminder = { Enabled = true } },
                isLoaded = function(name) return name == "EllesmereUIQoL" end,
                shouldNotLoad = true,
            })
            assert.equals(1, #queue)
            assert.equals("LFGReminder", queue[1].module)
        end)

        -- _G is shared across the whole run, so this one must put it back or
        -- every later spec inherits a disabled rival prompt.
        after_each(function() _G.EllesmereUIDB = nil end)

        it("resolver isActive returns false once the rival's prompt is disabled", function()
            _G.EllesmereUIDB = { teleportPrompt = { enabled = false } }
            local queue = KE:BuildConflictQueue({
                profile = { LFGReminder = { Enabled = true } },
                isLoaded = function(name, resolver)
                    if name ~= "EllesmereUIQoL" then return false end
                    if resolver and resolver.isActive then return resolver.isActive() end
                    return true
                end,
                shouldNotLoad = false,
            })
            assert.same({}, queue)
        end)

        describe("Mythic+ Tweaks resolver", function()
            -- Reaches apply/isActive through the queued item, so the queue
            -- ignores the resolver and does not empty itself first.
            local function mptResolver()
                return KE:BuildConflictQueue({
                    profile = { LFGReminder = { Enabled = true } },
                    isLoaded = function(name) return name == "MythicPlusTweaks" end,
                    shouldNotLoad = false,
                })[1].resolver
            end

            -- _G is shared across the whole run, so every case that seeds the
            -- rival's saved variable must put it back.
            after_each(function() _G.MythicPlusTweaksDB = nil end)

            -- `after` is a separate literal: comparing the saved variable
            -- against the table it IS would pass any write.
            local function off()
                return { moduleDb = { DungeonTeleports = { popupOnGroupCast = false, groupFormedPopup = false } } }
            end
            it("apply creates each missing level and refuses a non-table saved variable", function()
                for _, case in ipairs({
                    { name = "the saved variable is absent",      db = nil,               ok = true,  after = off() },
                    { name = "moduleDb is absent",                db = {},                ok = true,  after = off() },
                    { name = "DungeonTeleports is absent",        db = { moduleDb = {} }, ok = true,  after = off() },
                    { name = "the saved variable is not a table", db = "corrupt",         ok = false, after = "corrupt" },
                }) do
                    _G.MythicPlusTweaksDB = case.db
                    assert.equals(case.ok, mptResolver().apply(), case.name)
                    assert.same(case.after, _G.MythicPlusTweaksDB, case.name)
                end
            end)

            it("apply flips both popups in the table the addon already holds", function()
                local held = { popupOnGroupCast = true, chatMessage = true }
                _G.MythicPlusTweaksDB = { moduleDb = { DungeonTeleports = held } }
                assert.is_true(mptResolver().apply())
                assert.equals(held, _G.MythicPlusTweaksDB.moduleDb.DungeonTeleports)
                assert.same({ popupOnGroupCast = false, groupFormedPopup = false, chatMessage = true }, held)
            end)

            it("isActive is false once both popups are off or its teleport module is off", function()
                for _, case in ipairs({
                    { name = "both popups off",
                      db = { moduleDb = { DungeonTeleports = { popupOnGroupCast = false, groupFormedPopup = false } } },
                      active = false },
                    { name = "its teleport module off, popups on",
                      db = { modules = { DungeonTeleports = false },
                             moduleDb = { DungeonTeleports = { popupOnGroupCast = true } } },
                      active = false },
                    { name = "one popup unset",
                      db = { moduleDb = { DungeonTeleports = { popupOnGroupCast = false } } }, active = true },
                    { name = "the saved variable is absent", db = nil, active = true },
                }) do
                    _G.MythicPlusTweaksDB = case.db
                    assert.equals(case.active, mptResolver().isActive(), case.name)
                end
            end)
        end)
    end)

    describe("ReadyCheckConsumables conflict entry", function()
        -- Ignores the resolver on purpose: these cases reach apply/isActive
        -- through the queued item, so the queue must not empty itself first.
        local function rccEnv(enabled)
            return {
                profile = { ReadyCheckConsumables = { Enabled = enabled } },
                isLoaded = function(name) return name == "NorthernSkyRaidTools" end,
                shouldNotLoad = false,
            }
        end

        -- _G is shared across the whole run, so every case that seeds the
        -- rival's saved variable must put it back.
        after_each(function() _G.NSRT = nil end)

        it("queues one entry when the module is enabled and NorthernSkyRaidTools is loaded", function()
            local queue = KE:BuildConflictQueue(rccEnv(true))
            assert.equals(1, #queue)
            assert.equals("ReadyCheckConsumables", queue[1].module)
            assert.equals("NorthernSkyRaidTools", queue[1].source)
        end)

        it("queues nothing when the module is off", function()
            assert.same({}, KE:BuildConflictQueue(rccEnv(false)))
        end)

        -- The rival's own loader fills ReadyCheckSettings. Creating it here
        -- would seed a foreign addon's settings from a guess, so an absent
        -- table is a refusal, not a repair. `after` is a separate literal:
        -- comparing _G.NSRT against the table it IS would pass any write.
        for _, case in ipairs({
            { name = "NSRT is absent",              nsrt = nil, after = nil },
            { name = "ReadyCheckSettings is absent", nsrt = {},  after = {} },
        }) do
            it("apply returns false and writes nothing when " .. case.name, function()
                _G.NSRT = case.nsrt
                local resolver = KE:BuildConflictQueue(rccEnv(true))[1].resolver
                assert.is_false(resolver.apply())
                assert.same(case.after, _G.NSRT)
            end)
        end

        for _, case in ipairs({
            { name = "false once ConsumablesDisplay is false",
              nsrt = { ReadyCheckSettings = { ConsumablesDisplay = false } }, active = false },
            { name = "true when ReadyCheckSettings is absent", nsrt = {},  active = true },
            { name = "true when NSRT is absent",               nsrt = nil, active = true },
        }) do
            it("isActive is " .. case.name, function()
                _G.NSRT = case.nsrt
                local resolver = KE:BuildConflictQueue(rccEnv(true))[1].resolver
                assert.equals(case.active, resolver.isActive())
            end)
        end
    end)

    describe("GroupFinderPanel conflict entry", function()
        -- Consults the resolver, as LiveEnv does, so the rival's switch
        -- decides whether the row queues.
        local function gfEnv(enabled)
            return {
                profile = { GroupFinderPanel = { Enabled = enabled } },
                isLoaded = function(name, resolver)
                    if name ~= "EllesmereUIGroupFinder" then return false end
                    return resolver.isActive()
                end,
                shouldNotLoad = false,
            }
        end

        -- Ignores the resolver, so apply is reachable whatever the switch.
        local function gfResolver()
            return KE:BuildConflictQueue({
                profile = { GroupFinderPanel = { Enabled = true } },
                isLoaded = function(name) return name == "EllesmereUIGroupFinder" end,
                shouldNotLoad = false,
            })[1].resolver
        end

        -- _G is shared across the whole run, so every case that seeds the
        -- rival's saved variable must put it back.
        after_each(function() _G.EllesmereUIDB = nil end)

        -- Absent means OFF for this switch, the opposite of the tooltip and
        -- teleport switches, so only a literal true may prompt.
        it("queues only while the module is on and the rival's switch is true", function()
            for _, case in ipairs({
                { name = "both on",                    enabled = true,  db = { groupFinder = { enabled = true } },  n = 1 },
                { name = "switch unset",               enabled = true,  db = { groupFinder = {} },                  n = 0 },
                { name = "switch false",               enabled = true,  db = { groupFinder = { enabled = false } }, n = 0 },
                { name = "groupFinder absent",         enabled = true,  db = {},                                    n = 0 },
                { name = "saved variable not a table", enabled = true,  db = "corrupt",                             n = 0 },
                { name = "module off",                 enabled = false, db = { groupFinder = { enabled = true } },  n = 0 },
            }) do
                _G.EllesmereUIDB = case.db
                assert.equals(case.n, #KE:BuildConflictQueue(gfEnv(case.enabled)), case.name)
            end
        end)

        -- `after` is a separate literal: comparing the saved variable
        -- against the table it IS would pass any write.
        it("apply turns the switch off, creating a missing table, and refuses a non-table saved variable", function()
            for _, case in ipairs({
                { name = "switch on",                  db = { groupFinder = { enabled = true } }, ok = true,
                  after = { groupFinder = { enabled = false } } },
                { name = "groupFinder absent",         db = {},                                   ok = true,
                  after = { groupFinder = { enabled = false } } },
                { name = "saved variable not a table", db = "corrupt",                            ok = false,
                  after = "corrupt" },
                { name = "saved variable absent",      db = nil,                                  ok = false,
                  after = nil },
            }) do
                _G.EllesmereUIDB = case.db
                assert.equals(case.ok, gfResolver().apply(), case.name)
                assert.same(case.after, _G.EllesmereUIDB, case.name)
            end
        end)
    end)

    describe("KickTracker nameplate icons conflict entry", function()
        -- Ignores the resolver, so these cases test the KE side alone and
        -- reach apply/isActive whatever the rival's state.
        local function ktEnv(db)
            return {
                profile = { KickTracker = db },
                isLoaded = function(name) return name == "EllesmereUIMythicTimer" end,
                shouldNotLoad = false,
            }
        end
        local function ktResolver()
            return KE:BuildConflictQueue(ktEnv({ Enabled = true, PlateIcons = true }))[1].resolver
        end

        -- _G is shared across the whole run, so every case that seeds the
        -- rival's saved variable must put it back.
        after_each(function() _G._EMT_AceDB = nil end)

        -- The tracker draws icons only while PlateIcons is exactly true, so
        -- an unset key must not prompt.
        it("queues only while the tracker is on and its nameplate icons are exactly true", function()
            for _, case in ipairs({
                { name = "both on",     db = { Enabled = true,  PlateIcons = true },  n = 1 },
                { name = "icons off",   db = { Enabled = true,  PlateIcons = false }, n = 0 },
                { name = "icons unset", db = { Enabled = true },                      n = 0 },
                { name = "tracker off", db = { Enabled = false, PlateIcons = true },  n = 0 },
            }) do
                assert.equals(case.n, #KE:BuildConflictQueue(ktEnv(case.db)), case.name)
            end
        end)

        it("isActive is true only while the rival's tracker and its nameplate icons are on", function()
            for _, case in ipairs({
                { name = "on, icons unset",    db = { profile = { kickTracker = { enabled = true } } },                     active = true },
                { name = "on, icons on",       db = { profile = { kickTracker = { enabled = true, showPlates = true } } },  active = true },
                { name = "icons off",          db = { profile = { kickTracker = { enabled = true, showPlates = false } } }, active = false },
                { name = "tracker unset",      db = { profile = { kickTracker = {} } },                                     active = false },
                { name = "kickTracker absent", db = { profile = {} },                                                       active = false },
                { name = "profile absent",     db = {},                                                                     active = false },
                { name = "handle absent",      db = nil,                                                                    active = false },
            }) do
                _G._EMT_AceDB = case.db
                assert.equals(case.active, ktResolver().isActive(), case.name)
            end
        end)

        -- `after` is a separate literal: comparing the saved variable
        -- against the table it IS would pass any write.
        it("apply turns the icons off in the table the rival holds and refuses a missing level", function()
            local held = { enabled = true, showPlates = true }
            _G._EMT_AceDB = { profile = { kickTracker = held } }
            assert.is_true(ktResolver().apply())
            assert.equals(held, _G._EMT_AceDB.profile.kickTracker)
            assert.same({ enabled = true, showPlates = false }, held)

            for _, case in ipairs({
                { name = "kickTracker absent", db = { profile = {} }, after = { profile = {} } },
                { name = "profile absent",     db = {},               after = {} },
                { name = "handle absent",      db = nil,              after = nil },
            }) do
                _G._EMT_AceDB = case.db
                assert.is_false(ktResolver().apply(), case.name)
                assert.same(case.after, _G._EMT_AceDB, case.name)
            end
        end)

        it("GetModuleConflict reads the KE side as off once its feature key is off", function()
            for _, case in ipairs({
                { name = "icons off, tracker on", plateIcons = false, rival = "EllesmereUIMythicTimer" },
                { name = "icons on",              plateIcons = true,  rival = nil },
            }) do
                assert.equals(case.rival, KE:GetModuleConflict("KickTracker", ktEnv({
                    Enabled = true, PlateIcons = case.plateIcons,
                })), case.name)
            end
        end)
    end)
end)

describe("Core/Conflicts.lua prompt queue", function()
    local KE, prompts, disabled, printed

    -- Loads the module with SkinTooltips enabled and the named addons loaded,
    -- then fires the login event. _wow_mock's C_Timer.After runs callbacks
    -- immediately and the fake RunAfterCombat runs its closure inline, so the
    -- whole delayed scan completes synchronously.
    local function login(loadedNames)
        KE, prompts, disabled, printed = L.loadConflicts()
        KE.db.profile.Skinning = { Tooltips = { Enabled = true } }
        local loaded = {}
        for _, name in ipairs(loadedNames or {}) do loaded[name] = true end
        _G.C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
        _G.frames[1]:Fire("PLAYER_ENTERING_WORLD")
    end

    it("raises no prompt when nothing conflicts", function()
        login({})
        assert.equals(0, #prompts)
    end)

    it("raises one conflict prompt naming both owners", function()
        login({ "TipTac" })
        assert.equals(1, #prompts)
        assert.equals("Tooltip Conflict", prompts[1].title)
        assert.equals("|cff00ff00Use KitnEssentials|r", prompts[1].acceptText)
        assert.equals("Use TipTac", prompts[1].cancelText)
    end)

    it("disables the rival addon when the user picks KitnEssentials", function()
        login({ "TipTac" })
        prompts[1].onAccept()
        assert.same({ "TipTac" }, disabled)
    end)

    -- The mitigation for the accepted dismissal risk: Escape reaches onCancel,
    -- so every choice must announce itself in chat.
    it("announces each choice in chat", function()
        login({ "TipTac" })
        prompts[1].onAccept()
        assert.equals(1, #printed)
        assert.is_truthy(printed[1]:find("TipTac", 1, true))

        login({ "TipTac" })
        prompts[1].onCancel()
        assert.equals(1, #printed)
        assert.is_truthy(printed[1]:find("Tooltip", 1, true))
    end)

    it("disables the KE module when the user picks the rival", function()
        login({ "TipTac" })
        prompts[1].onCancel()
        assert.is_false(KE.db.profile.Skinning.Tooltips.Enabled)
        assert.same({}, disabled)
    end)

    it("follows a single answered conflict with one reload prompt", function()
        login({ "TipTac" })
        prompts[1].onAccept()
        assert.equals(2, #prompts)
        assert.is_true(prompts[2].reload)
    end)

    -- Regression guard. Firing a reload prompt per choice without setting
    -- pendingReload lets the singleton dialog replace the first reload prompt
    -- with the second conflict prompt before it can be clicked.
    it("shows both conflicts first, then exactly one reload prompt", function()
        login({ "TipTac", "TacoTip" })
        assert.equals(1, #prompts)
        assert.equals("Use TipTac", prompts[1].cancelText)

        prompts[1].onAccept()
        assert.equals(2, #prompts)
        assert.is_nil(prompts[2].reload)
        assert.equals("Use TacoTip", prompts[2].cancelText)

        prompts[2].onAccept()
        assert.equals(3, #prompts)
        assert.is_true(prompts[3].reload)
        assert.same({ "TipTac", "TacoTip" }, disabled)
    end)

    it("self-silences on a rescan once the module is off", function()
        login({ "TipTac" })
        prompts[1].onCancel()
        local answered = #prompts
        KE:ScanAddonConflicts()
        assert.equals(answered, #prompts)
    end)

    -- Regression guard for deviation 8. DisableAddOn does not unload the rival,
    -- so IsAddOnLoaded still reports it until the reload; without the
    -- enable-state check this rescan would re-raise the conflict the user just
    -- answered. There is no "already answered" set -- do not add one.
    it("self-silences on a rescan after the rival was disabled", function()
        login({ "TipTac" })
        prompts[1].onAccept()
        local answered = #prompts
        KE:ScanAddonConflicts()
        assert.equals(answered, #prompts)
    end)

    -- Regression guard for deviation 9. Draining the queue is what makes the
    -- duplicate observable: a rescan that wrongly appends leaves #prompts at 1
    -- either way, because the show guard still withholds it. The extra copies
    -- only surface once the open prompt is answered.
    it("ignores a rescan while a prompt is still open", function()
        login({ "TipTac", "TacoTip" })
        assert.equals(1, #prompts)
        KE:ScanAddonConflicts()
        prompts[1].onAccept()
        prompts[2].onAccept()
        assert.equals(3, #prompts)
        assert.is_true(prompts[3].reload)
    end)

    -- An unrelated KE:CreatePrompt replaces the singleton and drops our
    -- callbacks, so nothing would ever clear promptActive. Once no prompt is
    -- on screen the next scan must reclaim the queue instead of stalling --
    -- and must DISCARD the stranded tail, or the rebuild queues it twice.
    -- Two rivals are required: with one, the queue is already empty and a
    -- missing wipe cannot show.
    it("recovers a queue stranded by an unrelated prompt", function()
        login({ "TipTac", "TacoTip" })
        assert.equals(1, #prompts)      -- TipTac showing, TacoTip still queued
        KE.activePrompt = nil           -- the foreign prompt opened, then closed
        KE:ScanAddonConflicts()
        assert.equals(2, #prompts)
        assert.equals("Use TipTac", prompts[2].cancelText)
        prompts[2].onAccept()
        assert.equals(3, #prompts)
        assert.equals("Use TacoTip", prompts[3].cancelText)
        prompts[3].onAccept()
        assert.equals(4, #prompts)
        assert.is_true(prompts[4].reload)
    end)

    -- Regression guard for deviation 8's statelessness half. Nothing records
    -- "already answered", so turning the rival back on must bring the prompt
    -- back without a relog.
    it("re-arms once the rival is enabled again", function()
        login({ "TipTac" })
        prompts[1].onAccept()
        local answered = #prompts
        KE:ScanAddonConflicts()
        assert.equals(answered, #prompts)

        _G.C_AddOns.GetAddOnEnableState = function() return 2 end
        KE:ScanAddonConflicts()
        assert.equals(answered + 1, #prompts)
        assert.equals("Use TipTac", prompts[answered + 1].cancelText)
    end)

    it("raises nothing when the DB is not ready", function()
        KE, prompts = L.loadConflicts()
        KE.db = nil
        KE:ScanAddonConflicts()
        assert.equals(0, #prompts)
    end)

    -- A rival that exposes a switch for just the conflicting feature gets that
    -- switch flipped, NOT the whole addon disabled. EUI's Blizz UI Enhanced
    -- also skins eight unrelated panels, and a user choosing KE for tooltips
    -- did not ask to lose them.
    it("flips the rival's own switch when it has one", function()
        _G.EllesmereUIDB = {}
        login({ "EllesmereUIBlizzardSkin" })
        prompts[1].onAccept()
        assert.is_false(_G.EllesmereUIDB.customTooltips)
        assert.same({}, disabled)
        assert.is_truthy(printed[1]:find("tooltip reskin", 1, true))
    end)

    it("falls back to disabling the addon when the switch is unreachable", function()
        _G.EllesmereUIDB = nil
        login({ "EllesmereUIBlizzardSkin" })
        prompts[1].onAccept()
        assert.same({ "EllesmereUIBlizzardSkin" }, disabled)
    end)

    -- The resolver path's half of deviation 8. Flipping a switch leaves the
    -- addon loaded AND enabled, so neither of the other two checks can tell the
    -- conflict was settled; only the resolver's isActive can.
    it("self-silences on a rescan once the rival's switch is off", function()
        _G.EllesmereUIDB = {}
        login({ "EllesmereUIBlizzardSkin" })
        prompts[1].onAccept()
        local answered = #prompts
        KE:ScanAddonConflicts()
        assert.equals(answered, #prompts)
    end)
end)

describe("Core/Conflicts.lua one-feature rows in the prompt queue", function()
    local KE, prompts, disabled, printed

    -- login() above, with a chosen profile in place of the tooltip one.
    local function loginWith(profile, loadedNames)
        KE, prompts, disabled, printed = L.loadConflicts()
        KE.db.profile = profile
        local loaded = {}
        for _, name in ipairs(loadedNames) do loaded[name] = true end
        _G.C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
        _G.frames[1]:Fire("PLAYER_ENTERING_WORLD")
    end

    local function plates() return { profile = { kickTracker = { enabled = true } } } end

    -- _G is shared across the whole run, so every case that seeds the
    -- rival's saved variable must put it back.
    after_each(function() _G._EMT_AceDB = nil end)

    it("choosing the rival turns off only the nameplate icons", function()
        _G._EMT_AceDB = plates()
        loginWith({ KickTracker = { Enabled = true, PlateIcons = true, ShowBars = false } },
            { "EllesmereUIMythicTimer" })
        prompts[1].onCancel()
        assert.same({ Enabled = true, PlateIcons = false, ShowBars = false }, KE.db.profile.KickTracker)
        assert.same({}, disabled)
    end)

    it("names the feature, not a module, in the prompt and in chat", function()
        _G._EMT_AceDB = plates()
        loginWith({ KickTracker = { Enabled = true, PlateIcons = true } }, { "EllesmereUIMythicTimer" })
        assert.is_truthy(prompts[1].text:find("Kick Tracker nameplate icons", 1, true))
        assert.is_falsy(prompts[1].text:find("module", 1, true))
        assert.equals("Use EllesmereUI Kick Tracker", prompts[1].cancelText)
        prompts[1].onCancel()
        assert.is_falsy(printed[1]:find("module", 1, true))
    end)

    -- The switch became unreachable after the prompt showed. Disabling the
    -- addon instead would take its timer and kick bars with it, and nothing
    -- changed, so no reload is owed.
    it("names the manual path and disables nothing when the rival's switch cannot be written", function()
        _G._EMT_AceDB = plates()
        loginWith({ KickTracker = { Enabled = true, PlateIcons = true } }, { "EllesmereUIMythicTimer" })
        _G._EMT_AceDB = nil
        prompts[1].onAccept()
        assert.same({}, disabled)
        assert.is_truthy(printed[1]:find("Show on Nameplates", 1, true))
        assert.equals(1, #prompts)
    end)

    -- Both rows ask about the same addon. Choosing KE on the first disables
    -- it, so the second would offer a choice about an addon already off.
    it("skips a queued prompt whose rival an earlier answer turned off", function()
        _G._EMT_AceDB = plates()
        loginWith({
            MythicPlusTimer = { Enabled = true },
            KickTracker = { Enabled = true, PlateIcons = true },
        }, { "EllesmereUIMythicTimer" })
        assert.equals("Mythic+ Timer Conflict", prompts[1].title)
        prompts[1].onAccept()
        assert.equals(2, #prompts)
        assert.is_true(prompts[2].reload)
        assert.same({ "EllesmereUIMythicTimer" }, disabled)
    end)
end)

-- The /kes dispatcher lives in Core/Globals.lua and registers into
-- _G.SlashCmdList at file scope. loadGlobals stubs SlashCmdList, so a spec can
-- call the handler directly. Conflicts.lua is not loaded here: the branch is
-- nil-guarded, so a stub on the shared KE table is enough to observe it.
describe("/kes conflicts", function()
    local KE, handler

    before_each(function()
        KE = L.loadGlobals()
        handler = _G.SlashCmdList["KITNESSENTIALS"]
    end)

    it("runs the conflict rescan", function()
        local calls = 0
        KE.ScanAddonConflicts = function() calls = calls + 1 end
        handler("conflicts")
        assert.equals(1, calls)
    end)

end)

describe("Core/Conflicts.lua RareScanner row", function()
    local savedLibStub

    before_each(function()
        savedLibStub = _G.LibStub
    end)

    after_each(function()
        _G.LibStub = savedLibStub
    end)

    -- Stands in for AceAddon's registry holding the rival's addon object, or
    -- holding nothing.
    local function rival(addon)
        _G.LibStub = function()
            return {
                GetAddon = function(_, name)
                    if name == "RareScanner" then return addon end
                    return nil
                end,
            }
        end
    end

    local function holding(general)
        return { db = { profile = { general = general } } }
    end

    local function rareEnv(enabled)
        return {
            profile = { RareAlert = { Enabled = enabled } },
            isLoaded = function(name, resolver)
                if name ~= "RareScanner" then return false end
                if resolver and resolver.isActive then return resolver.isActive() end
                return true
            end,
            shouldNotLoad = false,
        }
    end

    local function resolver()
        local KE = L.loadConflicts(nil, { forever = true })
        rival(holding({ scanRares = true }))
        return KE:BuildConflictQueue(rareEnv(true))[1].resolver
    end

    it("queues one item on Forever with the module on, the rival loaded and its scan on", function()
        local KE = L.loadConflicts(nil, { forever = true })
        rival(holding({ scanRares = true }))
        local queue = KE:BuildConflictQueue(rareEnv(true))
        assert.equals(1, #queue)
        assert.equals("RareAlert", queue[1].module)
        assert.equals("RareScanner", queue[1].source)
    end)

    it("queues nothing with the module off or on a retail load", function()
        for _, row in ipairs({
            { name = "module off", forever = true,  enabled = false },
            { name = "retail",     forever = false, enabled = true },
        }) do
            local KE = L.loadConflicts(nil, { forever = row.forever })
            rival(holding({ scanRares = true }))
            assert.same({}, KE:BuildConflictQueue(rareEnv(row.enabled)), row.name)
        end
    end)

    it("isActive reads the scan flag, and an unreadable table as on", function()
        local isActive = resolver().isActive
        for _, row in ipairs({
            { name = "scan on",        addon = holding({ scanRares = true }),  active = true },
            { name = "scan unset",     addon = holding({}),                    active = true },
            { name = "scan off",       addon = holding({ scanRares = false }), active = false },
            { name = "no general",     addon = holding(nil),                   active = true },
            { name = "no profile",     addon = { db = {} },                    active = true },
            { name = "no db",          addon = {},                             active = true },
            { name = "addon not found", addon = nil,                           active = true },
        }) do
            rival(row.addon)
            assert.equals(row.active, isActive(), row.name)
        end
    end)

    it("apply turns the scan off in the table the rival holds", function()
        local apply = resolver().apply
        local general = { scanRares = true, scanContainers = true }
        rival(holding(general))
        assert.is_true(apply())
        assert.same({ scanRares = false, scanContainers = true }, general)
    end)

    it("apply refuses an unreadable table and writes nothing", function()
        local apply = resolver().apply
        for _, row in ipairs({
            { name = "no general",      addon = holding(nil), after = holding(nil) },
            { name = "no db",           addon = {},           after = {} },
            { name = "addon not found", addon = nil,          after = nil },
        }) do
            rival(row.addon)
            assert.is_false(apply(), row.name)
            assert.same(row.after, row.addon, row.name)
        end
    end)

    -- Choosing KitnEssentials takes only the rare scan: a refusal must never
    -- fall through to disabling the whole addon.
    it("a failed apply on accept prints the manual line and disables nothing", function()
        local KE, prompts, disabled, printed = L.loadConflicts(nil, { forever = true })
        rival(nil)
        KE.db.profile.RareAlert = { Enabled = true }
        _G.C_AddOns.IsAddOnLoaded = function(name) return name == "RareScanner" end
        _G.frames[1]:Fire("PLAYER_ENTERING_WORLD")
        assert.equals(1, #prompts)

        prompts[1].onAccept()

        assert.same({}, disabled)
        local lines = table.concat(printed, "\n")
        assert.is_truthy(lines:find("untick Search for rare NPCs in RareScanner's General options", 1, true))
    end)
end)

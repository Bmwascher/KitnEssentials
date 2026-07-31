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

        it("returns an empty queue when env is malformed", function()
            assert.same({}, KE:BuildConflictQueue(nil))
            assert.same({}, KE:BuildConflictQueue({}))
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

        it("returns nil for a module that is not in the registry", function()
            assert.is_nil(KE:GetModuleConflict("SkinBattlenet", env({
                loaded = { TipTac = true },
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

    it("shows the friendly name rather than the folder name", function()
        login({ "EllesmereUIBlizzardSkin" })
        assert.equals("Use EllesmereUI BlizzUI Enhanced", prompts[1].cancelText)
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

    -- Regression guard for deviation 4. The reference fires a reload prompt
    -- per choice and never sets pendingReload, so with KE's singleton dialog
    -- the first reload prompt would be replaced by the second conflict prompt
    -- before it could be clicked.
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

    it("is a no-op when Conflicts.lua never loaded", function()
        KE.ScanAddonConflicts = nil
        assert.has_no.errors(function() handler("conflicts") end)
    end)

    -- Stub KE.Print, NOT _G.print: Core/Globals.lua:13 captures print into a
    -- file-local at load, so a _G.print stub installed after loadGlobals is
    -- invisible and the assertion could never pass. The handler resolves
    -- KE.Print at call time, so replacing it on the shared table works.
    it("lists conflicts in the help output", function()
        local printed = {}
        KE.Print = function(_, msg) printed[#printed + 1] = msg end
        handler("nonsense")
        assert.equals(1, #printed)
        assert.is_truthy(printed[1]:find("conflicts", 1, true))
    end)
end)

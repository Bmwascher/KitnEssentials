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
end)

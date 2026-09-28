-- Tier 1: the Blizzard panel scaling rules KE invented (tiered test policy):
-- scale inheritance, the combat refusal rule, and the ownership, queue and
-- reposition orderings across combat and profile swaps.
--
-- The runtime cases drive a stateful fake of Blizzard frames and of the regen
-- watcher. The rules under test are orderings across calls (a release lands
-- before re-adoption, the latest queued intent wins, one reposition per
-- transition, a deferral outlives the AceEvent teardown), which no single
-- pure predicate holds. Frame layout, the real fit seam, taint and real
-- secret values stay with the in-game probe and smoke.
--
-- SECRET stands in for a secret value: arithmetic on it raises, as a real
-- secret does, so a missing guard fails loudly.
local helpers = require("dev.spec._helpers")

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- One fresh module per call: overrides land on the shipped defaults with the
-- master on, and opts.combat seeds InCombatLockdown.
local function load(overrides, opts)
    opts = opts or {}
    local combat = opts.combat or false
    local enabled = false
    local repositions = 0
    local aceEvents = {}
    local hooks = {}
    local watcher = { events = {}, arms = 0, scripts = {} }

    _G.CreateFrame = function()
        return {
            RegisterEvent = function(_, e) watcher.arms = watcher.arms + 1; watcher.events[e] = true end,
            UnregisterEvent = function(_, e) watcher.events[e] = nil end,
            SetScript = function(_, k, fn) watcher.scripts[k] = fn end,
        }
    end
    _G.InCombatLockdown = function() return combat end
    _G.issecretvalue = function(v) return v == SECRET end
    _G.hooksecurefunc = function(target, method, fn)
        if type(target) == "table" then hooks[method] = fn else hooks[target] = method end
    end
    _G.RegisterUIPanel = function() end
    _G.FrameUtil = { UpdateScaleForFitSpecific = function() end }
    _G.UpdateUIPanelPositions = function() repositions = repositions + 1 end

    local defaults = helpers.loadModule("Core/Defaults.lua"):GetDefaultDB().profile.PanelScale
    local db = copy(defaults)
    db.Enabled = true
    for k, v in pairs(overrides or {}) do db[k] = v end

    local modules = helpers.installAddonShim()
    local KE = { db = { profile = { PanelScale = db } } }
    helpers.loadModule("Modules/QoL/PanelScaleRegistry.lua", KE)
    -- busted keeps _G across the cases of one file, so no earlier case's fake
    -- frame may still answer to a registry name.
    for name in pairs(KE.PanelScaleRegistry.byName) do _G[name] = nil end
    helpers.loadModule("Modules/QoL/PanelScale.lua", KE)

    local PS = modules.PanelScale
    PS.SetEnabledState = function() end
    PS.IsEnabled = function() return enabled end
    PS.RegisterEvent = function(_, e, fn) aceEvents[e] = fn end
    PS.UnregisterAllEvents = function() for e in pairs(aceEvents) do aceEvents[e] = nil end end
    PS:OnInitialize()

    local c = {}
    -- The GUI master switch: the flag first, then Ace's enable or disable.
    function c.enable()
        KE.db.profile.PanelScale.Enabled = true
        enabled = true
        PS:OnEnable()
    end
    -- AceAddon unregisters every AceEvent handler straight after OnDisable.
    function c.disable()
        KE.db.profile.PanelScale.Enabled = false
        enabled = false
        PS:OnDisable()
        PS:UnregisterAllEvents()
    end
    -- ProfileManager's order: every module is rebound first, then a module
    -- that was and stays enabled gets ApplySettings.
    function c.switchProfile(newDB)
        KE.db.profile.PanelScale = newDB
        PS:UpdateDB()
        if enabled then PS:ApplySettings() end
    end
    function c.startCombat() combat = true end
    function c.endCombat() combat = false end
    -- Delivered through the watcher's own OnEvent, as the client does.
    function c.fireRegen()
        assert(watcher.events.PLAYER_REGEN_ENABLED, "the regen watcher is not armed")
        watcher.scripts.OnEvent(nil, "PLAYER_REGEN_ENABLED")
    end
    function c.regenArms() return watcher.arms end
    function c.regenLive() return watcher.events.PLAYER_REGEN_ENABLED and 1 or 0 end
    function c.fit(frame) hooks.UpdateScaleForFitSpecific(frame) end
    function c.repositions() return repositions end
    function c.resetRepositions() repositions = 0 end
    return PS, c
end

-- A Blizzard frame reduced to what the module reads and writes. _writes logs
-- every SetScale; opts.drift adds the client's float read-back error.
local function fakeFrame(name, scale, opts)
    opts = opts or {}
    local frame = {
        _scale = scale, _writes = {}, _scripts = {}, _hooks = 0,
        _shown = opts.shown or false, _protected = opts.protected or false,
    }
    function frame:GetName() return name end
    function frame:GetScale() return self._scale end
    function frame:SetScale(v)
        self._writes[#self._writes + 1] = v
        self._scale = v + (opts.drift or 0)
    end
    function frame:IsProtected() return self._protected end
    function frame:IsShown() return self._shown end
    function frame:HookScript(script, fn)
        self._scripts[script] = fn
        self._hooks = self._hooks + 1
    end
    _G[name] = frame
    return frame
end

describe("PanelScale policy", function()
    it("uses a category's override only while it is on, else the shared scale", function()
        for _, case in ipairs({
            { override = false, want = 0.8 },
            { override = true, want = 0.9 },
        }) do
            local PS = load({ Scale = 0.8, CoreScale = 0.9, CoreOverride = case.override })
            assert.equals(case.want, PS:GetCategoryScale("Core"))
        end
    end)

    it("treats a category as active only with the master and the category both on", function()
        for _, case in ipairs({
            { master = false, category = true, want = false },
            { master = true, category = true, want = true },
            { master = true, category = false, want = false },
        }) do
            local PS = load({ Enabled = case.master, CoreEnabled = case.category })
            assert.equals(case.want, PS:IsCategoryActive("Core"))
        end
    end)

    it("queues a combat write only for protected or unreadable protection, and CanMutate agrees", function()
        for _, case in ipairs({
            { combat = false, protected = true, want = "APPLY" },
            { combat = true, protected = false, want = "APPLY" },
            { combat = true, protected = true, want = "QUEUE" },
            { combat = true, protected = SECRET, want = "QUEUE" },
        }) do
            local PS = load(nil, { combat = case.combat })
            local secret = case.protected == SECRET
            local plain = case.protected
            if secret then plain = nil end
            assert.equals(case.want, PS.DecideMutation(case.combat, plain, secret))
            local frame = fakeFrame("CharacterFrame", 1, { protected = case.protected })
            assert.equals(case.want == "APPLY", PS:CanMutate(frame))
        end
    end)
end)

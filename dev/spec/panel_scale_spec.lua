-- Tier 1: the Blizzard panel scaling rules KE invented (tiered test policy):
-- scale inheritance, the combat refusal rule, and the ownership, queue and
-- reposition orderings across combat and profile swaps.
--
-- The runtime cases drive a stateful fake of Blizzard frames and of the regen
-- watcher. The rules under test are orderings across calls (a release lands
-- before re-adoption, only an adoption supersedes a queued release, one
-- reposition per transition, a deferral outlives the AceEvent teardown),
-- which no single pure predicate holds. Frame layout, the real fit seam,
-- taint and real secret values stay with the in-game probe and smoke.
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
    local walks, shows, owing = {}, {}, {}
    local KE = { db = { profile = { PanelScale = db } } }
    -- opts.edges installs a skin layer that records each walk's root set and
    -- each single-root refresh, and reports a root in `owing` as not settled;
    -- without it KE.Skins stays nil, as when the skinning module is absent.
    if opts.edges then
        KE.Skins = {
            RefreshEdgesUnderRoots = function(roots)
                local seen, settled = {}, true
                for root in pairs(roots) do
                    seen[root] = true
                    if owing[root] then settled = false end
                end
                walks[#walks + 1] = seen
                return settled
            end,
            RefreshEdgesUnder = function(root)
                shows[#shows + 1] = root
                return not owing[root]
            end,
        }
    end
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
    function c.walks() return walks end
    function c.shows() return shows end
    function c.resetEdges()
        for i = #walks, 1, -1 do walks[i] = nil end
        for i = #shows, 1, -1 do shows[i] = nil end
    end
    -- Shown, then the OnShow hook the module installed, as the client does.
    function c.show(frame)
        frame._shown = true
        frame._scripts.OnShow(frame)
    end
    function c.hide(frame) frame._shown = false end
    function c.owe(frame, on) owing[frame] = on or nil end
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

    it("clamps a stored scale the sliders cannot produce", function()
        for _, case in ipairs({
            { scale = 0, want = 0.5 },
            { scale = 5, want = 2 },
            { scale = "0.8", want = 1 },
        }) do
            local PS = load({ Scale = case.scale })
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

describe("PanelScale ownership", function()
    it("captures once, writes once and hooks once, and a repeat pass writes nothing despite float read-back", function()
        local PS, c = load({ Scale = 0.8 })
        local frame = fakeFrame("CharacterFrame", 1, { drift = 1e-7 })
        c.enable()
        PS:ApplySettings()
        PS:ReconcileAll()
        assert.same({ 0.8 }, frame._writes)
        assert.equals(1, frame._hooks)
        assert.equals(1, PS.frameState[frame].baseline)
    end)

    it("restores the captured scale on release and captures afresh on re-adoption", function()
        local PS, c = load({ Scale = 0.8 })
        local frame = fakeFrame("CharacterFrame", 0.9)
        c.enable()
        PS.db.CoreEnabled = false
        PS:ReconcileCategory("Core")
        assert.equals(0.9, frame._scale)
        assert.is_nil(PS.frameState[frame])

        frame._scale = 1.1
        PS.db.CoreEnabled = true
        PS:ReconcileCategory("Core")
        assert.equals(1.1, PS.frameState[frame].baseline)
        assert.equals(0.8, frame._scale)
    end)

    it("refuses ownership of a frame whose scale is secret at adoption", function()
        local PS, c = load({ Scale = 0.8 })
        local frame = fakeFrame("CharacterFrame", SECRET)
        c.enable()
        assert.is_nil(PS.frameState[frame])
        assert.same({}, frame._writes)
    end)

    it("keeps ownership but writes nothing while the current scale is secret", function()
        local PS, c = load({ Scale = 0.8 })
        local frame = fakeFrame("CharacterFrame", 1)
        c.enable()
        frame._scale = SECRET
        PS.db.Scale = 0.9
        PS:ApplySettings()
        assert.same({ 0.8 }, frame._writes)
        assert.is_not_nil(PS.frameState[frame])
    end)

    it("queues a protected combat write once and applies the settings current at regen", function()
        local PS, c = load({ Scale = 0.8 }, { combat = true })
        local frame = fakeFrame("CharacterFrame", 1, { protected = true })
        c.enable()
        PS:ReconcileAll()
        assert.same({}, frame._writes)
        assert.equals(1, c.regenArms())
        PS.db.Scale = 0.9
        c.endCombat()
        c.fireRegen()
        assert.equals(0.9, frame._scale)
        assert.equals(0, c.regenLive())
    end)

    it("finishes a restore queued before OnDisable after the AceEvent teardown", function()
        local PS, c = load({ Scale = 0.8 })
        local frame = fakeFrame("CharacterFrame", 1, { protected = true })
        c.enable()
        c.startCombat()
        c.disable()
        assert.equals(1, c.regenLive())
        c.endCombat()
        c.fireRegen()
        assert.equals(1, frame._scale)
        assert.is_nil(PS.frameState[frame])
    end)

    it("ends owned at the configured scale when re-enabled before a queued release drains", function()
        local PS, c = load({ Scale = 0.8 })
        local frame = fakeFrame("CharacterFrame", 1, { protected = true })
        c.enable()
        c.startCombat()
        c.disable()
        c.enable()
        c.endCombat()
        c.fireRegen()
        assert.equals(0.8, frame._scale)
        assert.equals(1, PS.frameState[frame].baseline)
    end)

    it("releases and re-adopts on a swap between enabled profiles, and not on an unchanged one", function()
        local PS, c = load({ Scale = 0.8 })
        local frame = fakeFrame("CharacterFrame", 1)
        c.enable()
        c.switchProfile(PS.db)
        assert.same({ 0.8 }, frame._writes)

        local other = copy(PS.db)
        other.Scale = 0.9
        c.switchProfile(other)
        assert.same({ 0.8, 1, 0.9 }, frame._writes)
    end)

    it("restores then re-adopts at the new scale when a protected root swaps in combat", function()
        local PS, c = load({ Scale = 0.8 })
        local frame = fakeFrame("CharacterFrame", 1, { protected = true })
        c.enable()
        c.startCombat()
        local other = copy(PS.db)
        other.Scale = 0.9
        c.switchProfile(other)
        assert.same({ 0.8 }, frame._writes)
        c.endCombat()
        c.fireRegen()
        assert.same({ 0.8, 1, 0.9 }, frame._writes)
        assert.equals(other, PS.ownedDB)
    end)

    it("adopts once under a profile switched to while disabled, with no release on the next settings pass", function()
        local PS, c = load({ Scale = 0.8 })
        local frame = fakeFrame("CharacterFrame", 1)
        c.enable()
        c.disable()
        local other = copy(PS.db)
        other.Scale = 0.9
        c.switchProfile(other)
        c.enable()
        PS:ApplySettings()
        assert.same({ 0.8, 1, 0.9 }, frame._writes)
    end)

    it("repositions once per visible transition, never for hidden-only ones, and counts unreadable visibility as visible", function()
        for _, case in ipairs({
            { shown = true, want = 1 },
            { shown = false, want = 0 },
            { shown = SECRET, want = 1 },
        }) do
            local PS, c = load({ Scale = 0.8 })
            fakeFrame("CharacterFrame", 1, { shown = case.shown })
            fakeFrame("PVEFrame", 1, { shown = case.shown })
            c.enable()
            c.resetRepositions()
            local other = copy(PS.db)
            other.Scale = 0.9
            c.switchProfile(other)
            assert.equals(case.want, c.repositions())
        end
    end)

    it("holds a reposition due in combat until the regen drain", function()
        local PS, c = load({ Scale = 0.8 })
        fakeFrame("CharacterFrame", 1, { shown = true })
        c.enable()
        c.resetRepositions()
        c.startCombat()
        PS.db.Scale = 0.9
        PS:ApplySettings()
        assert.equals(0, c.repositions())
        assert.equals(1, c.regenLive())
        c.endCombat()
        c.fireRegen()
        assert.equals(1, c.repositions())
    end)

    it("reapplies any managed root at Blizzard's fit, ignores other frames, and never repositions", function()
        local _, c = load({ Scale = 0.8 })
        local managed = fakeFrame("CharacterFrame", 1)
        local other = fakeFrame("GameMenuFrame", 1)
        c.enable()
        c.resetRepositions()
        managed._scale = 1
        c.fit(other)
        c.fit(managed)
        assert.same({}, other._writes)
        assert.equals(0.8, managed._scale)
        assert.equals(0, c.repositions())
    end)

    it("releases the old object when a new frame takes the same global name", function()
        local PS, c = load({ Scale = 0.8 })
        local old = fakeFrame("CharacterFrame", 1)
        c.enable()
        local new = fakeFrame("CharacterFrame", 1)
        PS:ReconcileAll()
        assert.equals(1, old._scale)
        assert.is_nil(PS.frameState[old])
        assert.equals(0.8, new._scale)
    end)

    it("keeps a queued release when a fit reaches the frame before regen", function()
        local PS, c = load({ Scale = 0.8 })
        local old = fakeFrame("CharacterFrame", 0.9, { protected = true })
        c.enable()
        c.startCombat()
        local new = fakeFrame("CharacterFrame", 1)
        PS:ReconcileAll()
        old._scale = 1
        c.fit(old)
        c.endCombat()
        c.fireRegen()
        assert.equals(0.9, old._scale)
        assert.is_nil(PS.frameState[old])
        assert.equals(0.8, new._scale)
    end)
end)

-- Which roots a batch's skin-edge refresh reaches, and the refresh a hidden
-- root is owed on its next show. The recorder at KE.Skins logs each walk's
-- root set and each single-root refresh; c.show fires the module's OnShow.
describe("PanelScale skin edges", function()
    it("walks a shown or unreadable root at the batch end and leaves a hidden one to one refresh on its next show", function()
        for _, case in ipairs({
            { shown = true, walked = true },
            { shown = SECRET, walked = true },
            { shown = false, walked = false },
        }) do
            local PS, c = load({ Scale = 0.8 }, { edges = true })
            local frame = fakeFrame("CharacterFrame", 1, { shown = case.shown })
            c.enable()
            -- Adoption already marked a hidden root; spend that mark so only
            -- the batch below can earn the refresh asserted at the end.
            if not case.walked then
                c.show(frame)
                c.hide(frame)
                assert.is_nil(PS.edgeDirty[frame])
            end
            c.resetEdges()
            PS.db.Scale = 0.9
            PS:ApplySettings()
            assert.same(case.walked and { { [frame] = true } } or {}, c.walks())
            c.resetEdges()
            c.show(frame)
            c.show(frame)
            assert.same(case.walked and {} or { frame }, c.shows())
        end
    end)

    it("drops a root's mark when a later batch walks it while shown", function()
        local PS, c = load({ Scale = 0.8 }, { edges = true })
        local frame = fakeFrame("CharacterFrame", 1)
        c.enable()
        assert.is_true(PS.edgeDirty[frame])
        frame._shown = true
        PS.db.Scale = 0.9
        PS:ApplySettings()
        assert.same({ { [frame] = true } }, c.walks())
        c.resetEdges()
        c.show(frame)
        assert.same({}, c.shows())
    end)

    it("refreshes a root released while hidden on its next show, with the module off", function()
        local PS, c = load({ Scale = 0.8 }, { edges = true })
        local frame = fakeFrame("CharacterFrame", 1)
        c.enable()
        c.show(frame)
        c.hide(frame)
        assert.is_nil(PS.edgeDirty[frame])
        c.disable()
        c.resetEdges()
        c.show(frame)
        assert.equals(1, frame._scale)
        assert.same({ frame }, c.shows())
    end)

    it("clears the changed roots at depth 0, so a later batch that changes nothing walks nothing", function()
        local PS, c = load({ Scale = 0.8 }, { edges = true })
        fakeFrame("CharacterFrame", 1, { shown = true })
        c.enable()
        c.resetEdges()
        PS.db.Scale = 0.9
        PS:ApplySettings()
        assert.equals(1, #c.walks())
        PS:ApplySettings()
        assert.equals(1, #c.walks())
    end)

    it("walks a batch's shown roots on the combat return, before the reposition waits for regen", function()
        local PS, c = load({ Scale = 0.8 }, { edges = true })
        local frame = fakeFrame("CharacterFrame", 1, { shown = true })
        c.enable()
        c.resetEdges()
        c.resetRepositions()
        c.startCombat()
        PS.db.Scale = 0.9
        PS:ApplySettings()
        assert.same({ { [frame] = true } }, c.walks())
        assert.equals(0, c.repositions())
        assert.equals(1, c.regenLive())
    end)

    it("walks once per outermost batch across a profile swap, holding every changed shown root", function()
        local PS, c = load({ Scale = 0.8 }, { edges = true })
        local a = fakeFrame("CharacterFrame", 1, { shown = true })
        local b = fakeFrame("PVEFrame", 1, { shown = true })
        c.enable()
        c.resetEdges()
        local other = copy(PS.db)
        other.Scale = 0.9
        c.switchProfile(other)
        assert.same({ { [a] = true, [b] = true } }, c.walks())
    end)

    it("keeps a mark whose show-time refresh does not settle, retries on the next show, and rests once settled", function()
        local _, c = load({ Scale = 0.8 }, { edges = true })
        local frame = fakeFrame("CharacterFrame", 1)
        c.enable()
        c.resetEdges()
        c.owe(frame, true)
        c.show(frame)
        c.hide(frame)
        c.owe(frame, false)
        c.show(frame)
        c.hide(frame)
        c.show(frame)
        assert.same({ frame, frame }, c.shows())
    end)

    it("marks every root of a batch walk left owed, and refreshes each on its next show", function()
        local PS, c = load({ Scale = 0.8 }, { edges = true })
        local a = fakeFrame("CharacterFrame", 1, { shown = true })
        local b = fakeFrame("PVEFrame", 1, { shown = true })
        c.enable()
        c.owe(a, true)
        PS.db.Scale = 0.9
        PS:ApplySettings()
        c.owe(a, false)
        c.hide(a)
        c.hide(b)
        c.resetEdges()
        c.show(a)
        c.show(b)
        assert.same({ a, b }, c.shows())
    end)
end)

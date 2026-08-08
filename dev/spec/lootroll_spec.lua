-- Modules/Skinning/LootRoll.lua -- the legacy CENTER -> BOTTOM conversion.
--
-- Why it exists: GroupLootContainer_Update sets the container's height to
-- reservedSize * (number of rolls) and anchors each roll relative to the
-- container's BOTTOM. Under a CENTER anchor the bottom edge moves every time
-- a roll is added, so every roll already on screen jumps. Anchoring the
-- bottom pins the first roll and lets the stack grow upward. A saved CENTER
-- value is converted rather than ignored, so an existing position does not
-- move on upgrade.

local L = require("dev.spec._ke_loader")

describe("LootRoll ApplyPosition", function()
    local LR, container

    -- Records the last SetPoint the module applied to the container.
    --
    -- GetPoint/IsShown are here for the DEBUG_LR tracer, which reads them on
    -- every ApplyPosition. They are not what these specs assert, but a mock
    -- missing them makes the whole file error the moment that flag is flipped
    -- on for a live probe, which has happened. A frame mock should model the
    -- frame, not just the calls one spec happens to check. GetWidth is here
    -- because GetStackAnchor sizes the anchor off the container's own
    -- dimensions -- not something these specs assert either.
    local function makeContainer(height, parent)
        return {
            _points = {},
            GetHeight = function(self) return height end,
            GetWidth = function(self) return 0 end,
            GetParent = function(self) return parent end,
            SetParent = function(self, p) self._parent = p end,
            ClearAllPoints = function(self) self._points = {} end,
            SetPoint = function(self, point, rel, relPoint, x, y)
                self._points[#self._points + 1] =
                    { point = point, relPoint = relPoint, x = x, y = y }
            end,
            GetPoint = function(self)
                local p = self._points[#self._points]
                if not p then return nil end
                return p.point, self, p.relPoint, p.x, p.y
            end,
            IsShown = function() return true end,
        }
    end

    before_each(function()
        LR, container = L.loadLootRoll()
    end)

    -- POSITIVE CONTROL. Without it, an ApplyPosition that returned early and
    -- never positioned anything would satisfy every assertion below.
    it("applies a saved BOTTOM anchor unchanged", function()
        LR.db = { Reposition = true, Position =
            { Point = "BOTTOM", RelPoint = "CENTER", X = 12, Y = 205 } }
        container(makeContainer(80))
        LR:ApplyPosition()
        local p = LR._lastPoint()
        assert.equal("BOTTOM", p.point)
        assert.equal(12, p.x)
        assert.equal(205, p.y)
    end)

    it("converts a legacy CENTER anchor to BOTTOM and shifts y by half the height", function()
        LR.db = { Reposition = true, Position =
            { Point = "CENTER", RelPoint = "CENTER", X = 0, Y = 250 } }
        container(makeContainer(80))
        LR:ApplyPosition()
        local p = LR._lastPoint()
        assert.equal("BOTTOM", p.point)
        assert.equal(210, p.y)   -- 250 - 80/2
    end)

    it("does not touch the db when it converts", function()
        -- The conversion is presentational. Writing it back would make the
        -- GUI's Y slider jump under the user on the next page open.
        LR.db = { Reposition = true, Position =
            { Point = "CENTER", RelPoint = "CENTER", X = 0, Y = 250 } }
        container(makeContainer(80))
        LR:ApplyPosition()
        assert.equal("CENTER", LR.db.Position.Point)
        assert.equal(250, LR.db.Position.Y)
    end)

    it("does not position the container when Reposition is off", function()
        LR.db = { Reposition = false, Position =
            { Point = "BOTTOM", RelPoint = "CENTER", X = 0, Y = 205 } }
        container(makeContainer(80))
        LR:ApplyPosition()
        assert.is_nil(LR._lastPoint())
    end)
end)

-- The container's OnShow hook must position the stack anchor SYNCHRONOUSLY.
--
-- Blizzard's managed-frame system runs AddManagedFrame from the container's own
-- OnShow (Blizzard_UIParent/Shared/UIParent.lua), which drags the container to
-- the bottom of the screen. Our hook runs after it and must re-anchor the roll
-- frames in that same execution -- a hook that only queued a deferred
-- correction would let them render one pass at the old spot first, the
-- "jumps to the bottom then back" report.
describe("LootRoll container OnShow hook", function()
    local LR, container

    local function makeHookableContainer()
        return {
            _points = {},
            _scripts = {},
            GetHeight = function() return 80 end,
            GetWidth = function() return 0 end,
            GetParent = function(self) return self._parent or _G.UIParent end,
            SetParent = function(self, p) self._parent = p end,
            ClearAllPoints = function(self) self._points = {} end,
            SetPoint = function(self, point, rel, relPoint, x, y)
                self._points[#self._points + 1] =
                    { point = point, relPoint = relPoint, x = x, y = y }
            end,
            HookScript = function(self, event, fn) self._scripts[event] = fn end,
            IsShown = function() return true end,
            GetPoint = function(self)
                local p = self._points[#self._points]
                if not p then return nil end
                return p.point, self, p.relPoint, p.x, p.y
            end,
        }
    end

    before_each(function()
        LR, container = L.loadLootRoll()
        LR.db = {
            Enabled = true, Replace = false, Skin = false, Reposition = true,
            Position = { Point = "BOTTOM", RelPoint = "CENTER", X = 0, Y = 205 },
        }
        -- AceAddon supplies IsEnabled in game; the headless shim does not, and
        -- every hook body guards on it.
        LR.IsEnabled = function() return true end
    end)

    it("positions the stack anchor during the handler, not on a later frame", function()
        local c = makeHookableContainer()
        container(c)
        LR:Setup()

        -- Positive control: Setup must actually install the hook, or the
        -- assertion below would be testing nothing at all.
        assert.is_function(c._scripts["OnShow"])

        LR.stackAnchor._points = {}   -- discard Setup's own ApplyPosition
        c._scripts["OnShow"]()        -- the frame Blizzard just re-anchored

        local p = LR._lastPoint()
        assert.is_table(p)
        assert.equal("BOTTOM", p.point)
        assert.equal(205, p.y)
    end)
end)

-- Replace mode must place the BONUS ROLL prompt at the roll-bar position.
--
-- Bonus rolls arrive on SPELL_CONFIRMATION_PROMPT, not START_LOOT_ROLL, so
-- SetupRollBars' unregister never intercepts them and they stay Blizzard's
-- frame at Blizzard's bottom-centre spot -- while every other roll obeys the
-- user's position. The fix re-anchors BonusRollFrame itself rather than moving
-- GroupLootContainer, so these specs pin the two things that make that choice
-- correct: it targets bar 1's defaults, and it leaves the reward toasts alone.
describe("LootRoll bonus roll anchoring", function()
    local LR

    local function makeFrame()
        return {
            _points = {},
            _shown = true,
            IsShown = function(self) return self._shown end,
            ClearAllPoints = function(self) self._points = {} end,
            SetPoint = function(self, point, rel, relPoint, x, y)
                self._points[#self._points + 1] =
                    { point = point, relPoint = relPoint, x = x, y = y }
            end,
        }
    end

    before_each(function()
        LR = L.loadLootRoll()
        LR.IsEnabled = function() return true end
        _G.BonusRollFrame = makeFrame()
    end)

    after_each(function() _G.BonusRollFrame = nil end)

    it("anchors the prompt to the roll bar position in Replace mode", function()
        LR.db = { Enabled = true, Replace = true,
            Position = { Point = "TOP", RelPoint = "TOP", X = 30, Y = -120 } }
        LR.AnchorBonusRoll()

        local p = _G.BonusRollFrame._points[1]
        assert.is_table(p)   -- positive control: it must anchor at all
        assert.equal("TOP", p.point)
        assert.equal(30, p.x)
        assert.equal(-120, p.y)
    end)

    it("uses bar 1's defaults, not the legacy container's", function()
        -- The legacy branch defaults to BOTTOM/0 and converts CENTER->BOTTOM
        -- because that container grows upward as rolls stack. Reusing either
        -- here would mis-place a single fixed-size frame.
        LR.db = { Enabled = true, Replace = true, Position = {} }
        LR.AnchorBonusRoll()

        local p = _G.BonusRollFrame._points[1]
        assert.equal("CENTER", p.point)
        assert.equal("CENTER", p.relPoint)
        assert.equal(250, p.y)
    end)

    it("does nothing in legacy mode", function()
        -- Legacy mode moves the container instead. Doing both would place the
        -- prompt twice, by two mechanisms that disagree.
        LR.db = { Enabled = true, Replace = false,
            Position = { Point = "TOP", RelPoint = "TOP", X = 30, Y = -120 } }
        LR.AnchorBonusRoll()
        assert.equal(0, #_G.BonusRollFrame._points)
    end)

    it("does nothing while the prompt is hidden", function()
        LR.db = { Enabled = true, Replace = true, Position = {} }
        _G.BonusRollFrame._shown = false
        LR.AnchorBonusRoll()
        assert.equal(0, #_G.BonusRollFrame._points)
    end)

    it("leaves the reward toasts to the alert frame system", function()
        -- BonusRollLootWonFrame / BonusRollMoneyWonFrame replace the prompt in
        -- the same container slot, but they set AlertFrame as their alert
        -- container and are handed to AlertFrame:AddAlertFrame -- the alert
        -- chain owns their placement. Touching them starts a fight we gain
        -- nothing from.
        LR.db = { Enabled = true, Replace = true, Position = {} }
        _G.BonusRollLootWonFrame = makeFrame()
        _G.BonusRollMoneyWonFrame = makeFrame()

        LR.AnchorBonusRoll()

        assert.equal(0, #_G.BonusRollLootWonFrame._points)
        assert.equal(0, #_G.BonusRollMoneyWonFrame._points)
        _G.BonusRollLootWonFrame, _G.BonusRollMoneyWonFrame = nil, nil
    end)
end)

describe("LootRoll RollBar_Get", function()
    local LR

    before_each(function()
        LR = L.loadLootRollBars()
    end)

    -- POSITIVE CONTROL: the indexed form must actually create bars, or the
    -- free-bar assertions below would pass against an empty pool.
    it("creates a bar on demand for an index", function()
        local bar = LR:RollBar_Get(1)
        assert.is_table(bar)
        assert.equal(1, #LR.RollBars)
        assert.equal(bar, LR:RollBar_Get(1))   -- same bar, not a second one
    end)

    it("hands out a bar with no rollID when called with no index", function()
        LR:RollBar_Get(1)
        LR:RollBar_Get(2)
        LR.RollBars[1].rollID = 42
        assert.equal(LR.RollBars[2], LR:RollBar_Get())
    end)

    it("returns nil when every bar is busy", function()
        -- The caller queues the roll in waitingRolls on nil. Returning a
        -- busy bar instead would silently drop an in-flight roll.
        LR:RollBar_Get(1)
        LR.RollBars[1].rollID = 42
        assert.is_nil(LR:RollBar_Get())
    end)

    it("treats the preview sentinel as busy", function()
        -- ShowPreview parks the string "PREVIEW" in rollID precisely so a
        -- real roll cannot steal a bar whose buttons have mouse disabled.
        LR:RollBar_Get(1)
        LR.RollBars[1].rollID = "PREVIEW"
        assert.is_nil(LR:RollBar_Get())
    end)
end)

-- The preview must neutralize EVERY roll button, not most of them.
--
-- Found in game: previewButtons listed four button keys while
-- CreateRollButton makes five, so Pass stayed
-- mouse-enabled during a preview and clicking it called
-- RollOnLoot("PREVIEW", 0) -- the sentinel rollID reaching the real API.
-- The two lists are file-locals, so this lifts each off the function that
-- closes over it rather than re-declaring the expected set here: a test
-- carrying its own copy of the button names would still pass if a sixth
-- button were added and left out of both.
describe("LootRoll preview button coverage", function()
    local function upvalue(fn, want)
        local i = 1
        while true do
            local name, value = debug.getupvalue(fn, i)
            if not name then return nil end
            if name == want then return value end
            i = i + 1
        end
    end

    it("neutralizes every button CreateRollButton makes", function()
        local LR = L.loadLootRollBars()
        local preview = upvalue(LR.ShowPreview, "previewButtons")
        local rollTypes = upvalue(LR.RollBars_Layout, "rollTypes")

        -- Positive controls: both seams must actually resolve, or every
        -- assertion below would pass vacuously against a nil table.
        assert.is_table(preview)
        assert.is_table(rollTypes)
        assert.is_true(#preview > 0)

        local neutralized = {}
        for _, key in ipairs(preview) do neutralized[key] = true end

        for _, key in pairs(rollTypes) do
            assert.is_true(neutralized[key],
                "roll button '" .. key .. "' is never mouse-disabled during preview")
        end
    end)

    it("restores exactly what it neutralized", function()
        -- ShowPreview and HidePreview must walk the SAME list, or a button
        -- disabled for the preview would stay dead for the next real roll.
        local LR = L.loadLootRollBars()
        assert.equal(upvalue(LR.ShowPreview, "previewButtons"),
                     upvalue(LR.HidePreview, "previewButtons"))
    end)
end)

-- The item icon must go through the shared skinning helper, not a hardcoded
-- SetTexCoord. Routing it through S.Icon is
-- what keeps this icon on the project's standard if that standard ever moves,
-- and it is the only way the icon picks up the helper's pixel snap.
describe("LootRoll item icon", function()
    it("is skinned through the shared icon helper", function()
        local LR, iconCalls = L.loadLootRollBars()
        LR:RollBar_Get(1)

        -- Positive control: the seam must record something, or the
        -- withBackdrop assertion below would pass against an empty list.
        assert.equal(1, #iconCalls)
        -- Falsy, not merely "not true": the button already carries its own
        -- S.Backdrop, and asking the helper for a second one would double the
        -- border on every roll bar.
        assert.is_falsy(iconCalls[1].withBackdrop)
    end)
end)

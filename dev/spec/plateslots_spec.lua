-- Core/PlateSlots.lua -- the slot allocator (which plate holds which slot, and
-- when a slot is let go) and the build runner (how far it walks, and when it
-- waits for the next frame). Plate events are fired at the recorder frame the
-- builder makes on Start; the verdict, the plate set and the next frame are
-- plain stubs.
local L = require("dev.spec._ke_loader")

describe("plate slots", function()
    local KE, frames, up, reasons, released

    local function start(cap)
        released = {}
        local slots = KE.PlateSlots.New({
            verdict = function(unit) return reasons[unit] end,
            cap = cap,
            onRelease = function(slot, unit) released[#released + 1] = slot .. "=" .. unit end,
        })
        slots:Start()
        return slots
    end

    before_each(function()
        up, reasons = {}, {}
        KE, frames = L.loadPlateSlots({
            UnitExists = function(unit) return up[unit] == true end,
        })
    end)

    it("keeps a counted unit in its slot and fills the lowest free slot in plate order", function()
        up.nameplate1, up.nameplate3 = true, true
        local slots = start(40)
        slots:ScanNow()
        assert.equals("nameplate1", slots:UnitOf(1))
        assert.equals("nameplate3", slots:UnitOf(2))

        reasons.nameplate1 = "dead"
        up.nameplate2 = true
        frames[#frames]:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        slots:ScanNow()
        assert.equals("nameplate2", slots:UnitOf(1))
        assert.equals("nameplate3", slots:UnitOf(2))
        assert.equals(2, slots:Total())
    end)

    it("counts no more than the cap and lets go of slots above a lowered cap", function()
        up.nameplate1, up.nameplate2, up.nameplate3 = true, true, true
        local slots = start(2)
        slots:ScanNow()
        assert.equals(2, slots:Total())
        assert.is_nil(slots:SlotOf("nameplate3"))

        slots:SetCap(1)
        assert.equals(1, slots:Total())
        assert.same({ "2=nameplate2" }, released)
    end)

    it("releases a plate's slot the moment the plate is removed", function()
        up.nameplate1 = true
        local slots = start(40)
        slots:ScanNow()
        up.nameplate1 = nil
        frames[#frames]:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        assert.is_nil(slots:UnitOf(1))
        assert.same({ "1=nameplate1" }, released)
    end)

    it("refills a freed slot from the next plate that passes on the rescan", function()
        up.nameplate1, up.nameplate2 = true, true
        local slots = start(1)
        slots:ScanNow()
        assert.equals("nameplate1", slots:UnitOf(1))
        frames[#frames]:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        slots:ScanNow()
        assert.equals("nameplate2", slots:UnitOf(1))
    end)

    it("rechecks one plate: lets it go when it stops counting, gives it a free slot when it starts", function()
        up.nameplate1, up.nameplate2 = true, true
        reasons.nameplate2 = "not in combat"
        local slots = start(40)
        slots:ScanNow()
        assert.equals(1, slots:Total())

        reasons.nameplate2 = nil
        slots:Recheck("nameplate2")
        assert.equals("nameplate2", slots:UnitOf(2))

        reasons.nameplate1 = "dead"
        slots:Recheck("nameplate1")
        assert.is_nil(slots:UnitOf(1))
        assert.same({ "1=nameplate1" }, released)
    end)
end)

describe("plate slots after a recheck", function()
    local KE, up, reasons, queue

    local function nextFrames()
        while #queue > 0 do
            local fn = table.remove(queue, 1)
            fn()
        end
    end

    before_each(function()
        up, reasons, queue = {}, {}, {}
        KE = L.loadPlateSlots({
            UnitExists = function(unit) return up[unit] == true end,
            C_Timer = {
                After = function(_, fn) queue[#queue + 1] = fn end,
                NewTicker = function() return { Cancel = function() end } end,
                NewTimer = function() return { Cancel = function() end } end,
            },
        })
    end)

    it("rescans after a recheck frees a slot, so a plate waiting past the cap takes it", function()
        up.nameplate1, up.nameplate2 = true, true
        local slots = KE.PlateSlots.New({
            verdict = function(unit) return reasons[unit] end,
            cap = 1,
        })
        slots:Start()
        nextFrames()
        assert.equals("nameplate1", slots:UnitOf(1))

        reasons.nameplate1 = "dead"
        slots:Recheck("nameplate1")
        nextFrames()
        assert.equals("nameplate2", slots:UnitOf(1))
    end)

    it("rescans after any recheck while relaxing is on, so one plate passing the strict rule ends the relaxed count", function()
        up.nameplate1, up.nameplate2 = true, true
        reasons.nameplate1, reasons.nameplate2 = "not in combat", "not in combat"
        local slots = KE.PlateSlots.New({
            verdict = function(unit, strict)
                if strict then return reasons[unit] end
                return nil
            end,
            relax = function() return true end,
            cap = 40,
        })
        slots:Start()
        nextFrames()
        assert.equals(2, slots:Total())

        reasons.nameplate2 = nil
        slots:Recheck("nameplate2")
        nextFrames()
        assert.is_nil(slots:SlotOf("nameplate1"))
        assert.equals(2, slots:SlotOf("nameplate2"))
    end)
end)

describe("plate build runner", function()
    local NewBuildRunner, queue, built

    local function nextFrame()
        local fn = table.remove(queue, 1)
        fn()
    end

    local function newRunner(workOn)
        built = {}
        return NewBuildRunner({
            buildSlot = function(slot)
                built[#built + 1] = slot
                return workOn[slot] == true
            end,
        })
    end

    before_each(function()
        queue = {}
        local KE = L.loadPlateSlots({
            C_Timer = {
                After = function(_, fn) queue[#queue + 1] = fn end,
                NewTicker = function() return { Cancel = function() end } end,
                NewTimer = function() return { Cancel = function() end } end,
            },
        })
        NewBuildRunner = KE.PlateSlots.NewBuildRunner
    end)

    it("ends the frame after a step that built something and walks empty steps in the same frame", function()
        local runner = newRunner({ [1] = true, [3] = true })
        runner:Run(3)
        assert.same({ 1 }, built)
        assert.equals(1, #queue)

        nextFrame()
        assert.same({ 1, 2, 3 }, built)
        assert.equals(3, runner:Built())
        assert.equals(0, #queue)
    end)

    it("never lowers its target, and walks from slot 1 again after Cancel", function()
        local runner = newRunner({})
        runner:Run(3)
        runner:Run(2)
        assert.same({ 1, 2, 3 }, built)
        runner:Run(5)
        assert.same({ 1, 2, 3, 4, 5 }, built)

        runner:Cancel()
        assert.equals(0, runner:Built())
        runner:Run(2)
        assert.same({ 1, 2, 3, 4, 5, 1, 2 }, built)
    end)
end)

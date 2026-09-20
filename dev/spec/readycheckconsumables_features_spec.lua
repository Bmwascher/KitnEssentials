-- The low-duration warning and the class checks. The warning predicate is
-- strictly under a threshold and never fires on a nil remaining or a nil
-- threshold; a slot whose aura expiry is secret paints no timer, no warning
-- colour and no glow; the class check owns exactly the hands a row's
-- requirements cover, gated on the spell being known and the hand holding
-- what the imbue needs; the class slot shows for a class with an entry whose
-- predicate holds and the off-hand slot shows for a shield the check owns;
-- an owned hand is ready only on the imbue, never on an oil, and its click
-- casts the imbue, or the shield under Instinctive Imbuements while the
-- slot still names the imbue; the ready check's remaining time drives the
-- countdown bar only when it is a safe positive number. Known spells, the
-- spec index, equipment and enchants are plain loader seams; the slot
-- button is a recording stub because the paint is read back from its text
-- and attributes.

local L = require("dev.spec._ke_loader")

local SWORD_1H, SHIELD = 7, 6
local MH, OH = 16, 17
local RITE_SANCTIFICATION, RITE_ADJURATION = 433568, 433583
local LIGHTNING_SHIELD, WATER_SHIELD = 192106, 52127
local WINDFURY, FLAMETONGUE, EARTHLIVING = 33757, 318038, 382021
local THUNDERSTRIKE_WARD, TIDECALLER_TALENT, TIDECALLER_GUARD = 462757, 445033, 457481
local INSTINCTIVE_IMBUEMENTS = 1270350

local function recordingButton()
    local btn = {
        statusTexture = { SetTexture = function(t, tex) t.tex = tex end, Show = function() end, Hide = function() end },
        texture = { SetDesaturated = function() end, SetTexture = function() end },
        timeLeft = {},
        countText = { SetText = function() end },
        click = { attributes = {}, shown = false },
    }
    btn.timeLeft.SetText = function(_, s) btn.text = s end
    btn.timeLeft.SetTextColor = function(_, r, g, b) btn.color = { r, g, b } end
    btn.click.SetAttribute = function(_, k, v) btn.click.attributes[k] = v end
    btn.click.Show = function() btn.click.shown = true end
    btn.click.Hide = function() btn.click.shown = false end
    return btn
end

local function equip(seams, invSlot, subclass, classID)
    local itemID = 100000 + invSlot
    seams.equipped[invSlot] = itemID
    seams.itemInfo[itemID] = { classID or 2, subclass }
end

describe("ReadyCheckConsumables low-duration predicate", function()
    it("warns strictly under the threshold and never on a nil side", function()
        local RCC = L.loadReadyCheckConsumables()
        local cases = {
            { remain = 599, threshold = 600, low = true },
            { remain = 600, threshold = 600, low = false },
            { remain = 601, threshold = 600, low = false },
            { remain = nil, threshold = 600, low = false },
            { remain = 30,  threshold = nil, low = false },
        }
        for i, c in ipairs(cases) do
            assert.equals(c.low, RCC._IsLowDuration(c.remain, c.threshold), "case " .. i)
        end
    end)
end)

describe("ReadyCheckConsumables timer bar seconds", function()
    it("returns a safe positive number and nil for secret, nil and zero", function()
        local RCC, _, seams = L.loadReadyCheckConsumables()
        local cases = {
            { value = 35,           seconds = 35 },
            { value = seams.SECRET, seconds = nil },
            { value = nil,          seconds = nil },
            { value = 0,            seconds = nil },
        }
        for i, c in ipairs(cases) do
            assert.equals(c.seconds, RCC._TimerBarSeconds(c.value), "case " .. i)
        end
    end)
end)

describe("ReadyCheckConsumables low-duration paint", function()
    it("paints no timer, no warning colour and no glow when the aura's expiry is secret", function()
        local RCC, _, seams = L.loadReadyCheckConsumables({ GetTime = function() return 1000 end })
        RCC.db.LowDurationWarning = true
        RCC.db.LowDurationMinutes = 10
        RCC.db.DurationColor = { 0.5, 0.5, 0.5, 1 }
        local btn = recordingButton()
        RCC.buttons = { food = btn }
        local FOOD_BUFF = 1284616

        RCC:UpdateFood({ [FOOD_BUFF] = { spellId = FOOD_BUFF, expirationTime = seams.SECRET } })
        assert.equals("", btn.text)
        assert.same({ 0.5, 0.5, 0.5 }, btn.color)
        assert.equals(0, seams.glow.starts)

        RCC:UpdateFood({ [FOOD_BUFF] = { spellId = FOOD_BUFF, expirationTime = 1300 } })
        assert.equals("5m", btn.text)
        assert.same({ 1, 0.3, 0.3 }, btn.color)
        assert.equals(1, seams.glow.starts)
    end)
end)

describe("ReadyCheckConsumables class check resolution", function()
    local function load(class, spec, known)
        local RCC, _, seams = L.loadReadyCheckConsumables()
        RCC.db.ClassChecks = true
        seams.playerClass = class
        seams.spec = spec
        for _, id in ipairs(known) do seams.knownSpells[id] = true end
        return RCC, seams
    end

    it("owns the hands each shipped row requires and casts that row's spells", function()
        local cases = {
            { name = "Paladin Sanctification", class = "PALADIN", known = { RITE_SANCTIFICATION },
              mh = SWORD_1H, hands = { [MH] = { cast = RITE_SANCTIFICATION, applyToSlot = true } } },
            { name = "Paladin Adjuration", class = "PALADIN", known = { RITE_ADJURATION },
              mh = SWORD_1H, hands = { [MH] = { cast = RITE_ADJURATION, applyToSlot = true } } },
            { name = "Enhancement", class = "SHAMAN", spec = 2, known = { WINDFURY, FLAMETONGUE },
              mh = SWORD_1H, oh = SWORD_1H, shield = LIGHTNING_SHIELD,
              hands = { [MH] = { cast = WINDFURY }, [OH] = { cast = FLAMETONGUE } } },
            { name = "Elemental", class = "SHAMAN", spec = 1, known = { FLAMETONGUE, THUNDERSTRIKE_WARD },
              mh = SWORD_1H, oh = "shield", shield = LIGHTNING_SHIELD,
              hands = { [MH] = { cast = FLAMETONGUE }, [OH] = { cast = THUNDERSTRIKE_WARD } } },
            { name = "Restoration", class = "SHAMAN", spec = 3, known = { EARTHLIVING, TIDECALLER_TALENT },
              mh = SWORD_1H, oh = "shield", shield = WATER_SHIELD,
              hands = { [MH] = { cast = EARTHLIVING }, [OH] = { cast = TIDECALLER_GUARD } } },
            { name = "Enhancement with Instinctive Imbuements", class = "SHAMAN", spec = 2,
              known = { WINDFURY, FLAMETONGUE, INSTINCTIVE_IMBUEMENTS },
              mh = SWORD_1H, oh = SWORD_1H, shield = LIGHTNING_SHIELD,
              hands = { [MH] = { cast = WINDFURY, clickCast = LIGHTNING_SHIELD },
                        [OH] = { cast = FLAMETONGUE, clickCast = LIGHTNING_SHIELD } } },
        }
        for _, c in ipairs(cases) do
            local RCC, seams = load(c.class, c.spec, c.known)
            if c.mh then equip(seams, MH, c.mh) end
            if c.oh == "shield" then equip(seams, OH, SHIELD, 4) elseif c.oh then equip(seams, OH, c.oh) end
            local check = RCC:_ActiveClassCheck()
            assert.is_not_nil(check, c.name)
            assert.equals(c.shield, check.shield, c.name)
            for invSlot, hand in pairs(c.hands) do
                assert.is_not_nil(check.hands[invSlot], c.name .. " slot " .. invSlot)
                assert.equals(hand.cast, check.hands[invSlot].cast, c.name .. " slot " .. invSlot)
                assert.equals(hand.clickCast or hand.cast, check.hands[invSlot].clickCast, c.name .. " slot " .. invSlot)
                assert.equals(hand.applyToSlot, check.hands[invSlot].applyToSlot, c.name .. " slot " .. invSlot)
            end
            for invSlot in pairs(check.hands) do
                assert.is_not_nil(c.hands[invSlot], c.name .. " owns slot " .. invSlot)
            end
        end
    end)

    it("skips a hand whose gate spell is unknown, whose imbue needs a shield it lacks, or that holds no weapon", function()
        local cases = {
            { name = "Elemental without Flametongue", spec = 1, known = { THUNDERSTRIKE_WARD },
              mh = SWORD_1H, oh = "shield", owned = { [OH] = true } },
            { name = "Elemental without a shield", spec = 1, known = { FLAMETONGUE, THUNDERSTRIKE_WARD },
              mh = SWORD_1H, oh = SWORD_1H, owned = { [MH] = true } },
            { name = "Enhancement with an empty off hand", spec = 2, known = { WINDFURY, FLAMETONGUE },
              mh = SWORD_1H, owned = { [MH] = true } },
        }
        for _, c in ipairs(cases) do
            local RCC, seams = load("SHAMAN", c.spec, c.known)
            if c.mh then equip(seams, MH, c.mh) end
            if c.oh == "shield" then equip(seams, OH, SHIELD, 4) elseif c.oh then equip(seams, OH, c.oh) end
            local check = RCC:_ActiveClassCheck()
            local owned = {}
            for invSlot in pairs(check.hands) do owned[invSlot] = true end
            assert.same(c.owned, owned, c.name)
        end
    end)

    it("resolves nothing while the toggle is off, for a class without rows, or for a Paladin without a rite", function()
        local cases = {
            { class = "SHAMAN", spec = 2, known = { WINDFURY, FLAMETONGUE }, toggle = false },
            { class = "WARRIOR", spec = 1, known = { WINDFURY }, toggle = true },
            { class = "PALADIN", spec = 2, known = {}, toggle = true },
        }
        for i, c in ipairs(cases) do
            local RCC, seams = load(c.class, c.spec, c.known)
            RCC.db.ClassChecks = c.toggle
            equip(seams, MH, SWORD_1H)
            assert.is_nil(RCC:_ActiveClassCheck(), "case " .. i)
        end
    end)
end)

describe("ReadyCheckConsumables class-check visibility", function()
    it("shows the class slot for an entry whose predicate holds, and the off hand for a shield the check owns", function()
        local cases = {
            { class = "WARLOCK", spec = 1, known = {}, oh = nil, classSlot = true, offhand = false },
            { class = "SHAMAN", spec = 1, known = { FLAMETONGUE, THUNDERSTRIKE_WARD }, oh = "shield", classSlot = true, offhand = true },
            { class = "SHAMAN", spec = 1, known = { FLAMETONGUE }, oh = "shield", classSlot = true, offhand = false },
            { class = "SHAMAN", spec = nil, known = {}, oh = "shield", classSlot = false, offhand = false },
            { class = "PALADIN", spec = 2, known = { RITE_SANCTIFICATION }, oh = "shield", classSlot = false, offhand = false },
            { class = "WARRIOR", spec = 1, known = {}, oh = SWORD_1H, classSlot = false, offhand = true },
        }
        for i, c in ipairs(cases) do
            local RCC, _, seams = L.loadReadyCheckConsumables()
            RCC.db.ClassChecks = true
            RCC.IsWarlockInGroup = function() return false end
            seams.playerClass = c.class
            seams.spec = c.spec
            for _, id in ipairs(c.known) do seams.knownSpells[id] = true end
            equip(seams, MH, SWORD_1H)
            if c.oh == "shield" then equip(seams, OH, SHIELD, 4) elseif c.oh then equip(seams, OH, c.oh) end
            local visibility = RCC:_ComputeVisibility()
            assert.equals(c.classSlot, visibility[7], "class slot, case " .. i)
            assert.equals(c.offhand, visibility[4], "off hand, case " .. i)
        end
    end)
end)

describe("ReadyCheckConsumables owned hand paint", function()
    it("is ready on the imbue and not on an oil, names the imbue, and the click casts the imbue or the shield", function()
        local cases = {
            { enchant = 5401, ready = true },
            { enchant = 8052, ready = false },
            { enchant = nil,  ready = false },
            { enchant = 5401, ready = true, instinctive = true },
        }
        for i, c in ipairs(cases) do
            local RCC, _, seams = L.loadReadyCheckConsumables()
            RCC.db.ClassChecks = true
            seams.playerClass = "SHAMAN"
            seams.spec = 2
            seams.knownSpells[WINDFURY] = true
            seams.knownSpells[FLAMETONGUE] = true
            if c.instinctive then seams.knownSpells[INSTINCTIVE_IMBUEMENTS] = true end
            equip(seams, MH, SWORD_1H)
            seams.bagCounts[243734] = 5
            seams.itemNames[243734] = "oil"
            if c.enchant then seams.enchants[MH] = { enchantID = c.enchant, remainingTimeMs = 3600000 } end
            local btn = recordingButton()
            RCC.buttons = { oil = btn }
            RCC:_ComputeVisibility()
            RCC:UpdateWeaponEnchant("oil", MH)
            local clickSpell = c.instinctive and LIGHTNING_SHIELD or WINDFURY
            assert.equals(c.ready and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\RaidFrame\\ReadyCheck-NotReady",
                btn.statusTexture.tex, "case " .. i)
            assert.equals(c.ready and "60m" or "", btn.text, "case " .. i)
            assert.equals("macro", btn.click.attributes.type, "case " .. i)
            assert.equals("/stopmacro [combat]\n/cast spell " .. clickSpell, btn.click.attributes.macrotext, "case " .. i)
            assert.is_true(btn.click.shown, "case " .. i)
            assert.is_nil(btn.nominatedItem, "case " .. i)
            assert.equals(WINDFURY, btn.nominatedSpell, "case " .. i)
        end
    end)
end)

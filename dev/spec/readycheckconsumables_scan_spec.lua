-- The aura walk and the weapon-enchant read on ReadyCheckConsumables. The
-- walk must reach every helpful aura however many there are and however
-- the slot API pages them, and must keep skipping secret spellIds; the
-- enchant read must treat a slot that returns nothing as "no enchant". The
-- walk's shape (nil batch size, a callback that never ends it) is only
-- observable through what a paged provider hands back, so the loader's
-- paging fake is the seam. Secret values here are a declared sentinel, not
-- the runtime's.

local L = require("dev.spec._ke_loader")

describe("ReadyCheckConsumables ScanPlayerAuras", function()
    local RCC, seams

    local function fill(n)
        for slot = 1, n do seams.auras[slot] = { spellId = 100000 + slot } end
    end

    before_each(function()
        local loaded = { L.loadReadyCheckConsumables() }
        RCC, seams = loaded[1], loaded[3]
    end)

    it("maps an aura past the fortieth slot", function()
        fill(45)
        local auras = RCC:ScanPlayerAuras()
        assert.is_not_nil(auras[100045])
    end)

    it("reads the second page when the provider hands back a continuation token", function()
        fill(45)
        seams.auraPageSize = 40
        local auras = RCC:ScanPlayerAuras()
        assert.is_not_nil(auras[100041])
        assert.is_not_nil(auras[100045])
    end)

    it("skips a secret spellId and still maps the rest", function()
        fill(3)
        seams.auras[2].spellId = seams.SECRET
        local auras = RCC:ScanPlayerAuras()
        local n = 0
        for _ in pairs(auras) do n = n + 1 end
        assert.equals(2, n)
        assert.is_not_nil(auras[100001])
        assert.is_not_nil(auras[100003])
    end)
end)

describe("ReadyCheckConsumables UpdateWeaponEnchant", function()
    it("paints not-ready without erroring when the slot returns nothing", function()
        local RCC = L.loadReadyCheckConsumables()
        local desaturated, timeText
        RCC.buttons = {
            oil = {
                statusTexture = { SetTexture = function() end, Show = function() end },
                texture = { SetDesaturated = function(_, on) desaturated = on end },
                timeLeft = { SetText = function(_, s) timeText = s end },
                countText = { SetText = function() end },
            },
        }
        RCC:UpdateWeaponEnchant("oil", 16)
        assert.is_true(desaturated)
        assert.equals("", timeText)
    end)
end)

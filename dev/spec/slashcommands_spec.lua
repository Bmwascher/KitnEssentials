local loader = require("dev.spec._ke_loader")

describe("KE:HasAuraAddon", function()
    local function withInstalled(names)
        local set = {}
        for _, n in ipairs(names) do set[n] = true end
        return loader.loadSlashCommands({
            C_AddOns = {
                GetAddOnInfo = function(name)
                    if set[name] then return name end
                    error("addon not found: " .. tostring(name))
                end,
            },
        })
    end

    it("reports true when WeakAuras is installed", function()
        local KE = withInstalled({ "WeakAuras" })
        assert.is_true(KE:HasAuraAddon())
    end)

    it("reports true when M33kAuras is installed", function()
        local KE = withInstalled({ "M33kAuras" })
        assert.is_true(KE:HasAuraAddon())
    end)

    it("reports true when M33kAurasOptions is installed", function()
        local KE = withInstalled({ "M33kAurasOptions" })
        assert.is_true(KE:HasAuraAddon())
    end)

    it("reports false when no aura addon is installed", function()
        local KE = withInstalled({})
        assert.is_false(KE:HasAuraAddon())
    end)
end)

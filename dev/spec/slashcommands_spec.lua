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

describe("/wa gating", function()
    local function withAuraAddons(names, settings)
        local set = {}
        for _, n in ipairs(names) do set[n] = true end
        local KE = loader.loadSlashCommands({
            C_AddOns = {
                GetAddOnInfo = function(name)
                    if set[name] then return name end
                    error("addon not found: " .. tostring(name))
                end,
            },
        })
        for key, value in pairs(settings or {}) do
            KE.db.profile.SlashCommands[key] = value
        end
        return KE
    end

    it("registers /wa when nothing else owns it and the setting is on", function()
        local KE = withAuraAddons({}, { CDMEnabled = true, WAEnabled = true })
        KE:ApplySlashCommands()
        assert.are.equal("/cd", _G.SLASH_KE_CDM1)
        assert.are.equal("/wa", _G.SLASH_KE_CDM2)
    end)

    it("leaves /cd alone when /wa is switched off", function()
        local KE = withAuraAddons({}, { CDMEnabled = true, WAEnabled = false })
        KE:ApplySlashCommands()
        assert.are.equal("/cd", _G.SLASH_KE_CDM1)
        assert.is_nil(_G.SLASH_KE_CDM2)
    end)

    it("treats a missing setting as on", function()
        local KE = withAuraAddons({}, { CDMEnabled = true })
        KE:ApplySlashCommands()
        assert.are.equal("/wa", _G.SLASH_KE_CDM2)
    end)

    it("still yields /wa to an installed aura addon while the setting is on", function()
        local KE = withAuraAddons({ "WeakAuras" }, { CDMEnabled = true, WAEnabled = true })
        KE:ApplySlashCommands()
        assert.is_nil(_G.SLASH_KE_CDM2)
    end)

    it("drops /wa on a re-apply after the setting is switched off", function()
        local KE = withAuraAddons({}, { CDMEnabled = true, WAEnabled = true })
        KE:ApplySlashCommands()
        assert.are.equal("/wa", _G.SLASH_KE_CDM2)
        KE.db.profile.SlashCommands.WAEnabled = false
        KE:ApplySlashCommands()
        assert.is_nil(_G.SLASH_KE_CDM2)
    end)

    it("reports and sets the state through its accessors", function()
        local KE = withAuraAddons({}, { CDMEnabled = true, WAEnabled = true })
        KE:ApplySlashCommands()
        assert.is_true(KE:IsWAEnabled())
        assert.is_false(KE:SetWAEnabled(false))
        assert.is_false(KE.db.profile.SlashCommands.WAEnabled)
        assert.is_nil(_G.SLASH_KE_CDM2)
    end)
end)

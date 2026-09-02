local loader = require("dev.spec._ke_loader")

describe("KE:HasAuraAddon", function()
    local function withInstalled(names)
        local set = {}
        for _, n in ipairs(names) do set[n] = true end
        return loader.loadSlashCommands({
            C_AddOns = {
                DoesAddOnExist = function(name) return set[name] == true end,
            },
        })
    end

    it("reports true when WeakAuras, M33kAuras, or M33kAurasOptions is installed", function()
        for _, name in ipairs({ "WeakAuras", "M33kAuras", "M33kAurasOptions" }) do
            local KE = withInstalled({ name })
            assert.is_true(KE:HasAuraAddon())
        end
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
                DoesAddOnExist = function(name) return set[name] == true end,
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

    -- The chat engine reads the alias globals only while it imports the command
    -- table, so a state change that leaves the handler in place registers
    -- nothing. These two pin the re-import path in both directions.
    it("writes the handler back so a newly added alias gets imported", function()
        local KE = withAuraAddons({}, { CDMEnabled = true, WAEnabled = false })
        KE:ApplySlashCommands()
        assert.is_function(_G.SlashCmdList.KE_CDM)

        -- Stand in for the engine having imported and cleared the entry.
        _G.SlashCmdList.KE_CDM = nil
        KE.db.profile.SlashCommands.WAEnabled = true
        KE:ApplySlashCommands()

        assert.are.equal("/wa", _G.SLASH_KE_CDM2)
        assert.is_function(_G.SlashCmdList.KE_CDM)
    end)

    it("drops a resolved alias out of the chat caches when /wa goes off", function()
        local KE = withAuraAddons({}, { CDMEnabled = true, WAEnabled = true })
        KE:ApplySlashCommands()
        -- Stand in for the engine having already resolved both commands.
        _G.hash_SlashCmdList["/WA"] = _G.SlashCmdList.KE_CDM
        _G.hash_ChatTypeInfoList["/WA"] = "KE_CDM"

        KE.db.profile.SlashCommands.WAEnabled = false
        KE:ApplySlashCommands()

        assert.is_nil(_G.hash_SlashCmdList["/WA"])
        assert.is_nil(_G.hash_ChatTypeInfoList["/WA"])
    end)

end)

describe("wa command handling", function()
    local function loaded(settings)
        local KE = loader.loadSlashCommands({
            C_AddOns = {
                DoesAddOnExist = function() return false end,
            },
        })
        for key, value in pairs(settings or {}) do
            KE.db.profile.SlashCommands[key] = value
        end
        -- The loader's stub KE carries only db and Print. HandleWACommand
        -- formats command names through the accent helper, so the stub needs a
        -- pass-through rather than the module needing a nil guard.
        KE.ColorTextByTheme = function(_, text) return text end
        KE:ApplySlashCommands()
        return KE
    end

    it("switches the alias off and back on", function()
        local KE = loaded({ CDMEnabled = true, WAEnabled = true })
        KE:HandleWACommand("off")
        assert.is_false(KE.db.profile.SlashCommands.WAEnabled)
        assert.is_nil(_G.SLASH_KE_CDM2)
        KE:HandleWACommand("on")
        assert.is_true(KE.db.profile.SlashCommands.WAEnabled)
        assert.are.equal("/wa", _G.SLASH_KE_CDM2)
    end)

    it("leaves the setting alone for any other argument", function()
        local KE = loaded({ CDMEnabled = true, WAEnabled = true })
        KE:HandleWACommand("")
        assert.is_true(KE.db.profile.SlashCommands.WAEnabled)
        KE:HandleWACommand("banana")
        assert.is_true(KE.db.profile.SlashCommands.WAEnabled)
    end)

end)

describe("/kes wa dispatch", function()
    local KE, handler

    before_each(function()
        KE = loader.loadGlobals()
        handler = _G.SlashCmdList["KITNESSENTIALS"]
    end)

    it("passes the argument through for each accepted form", function()
        local seen = {}
        KE.HandleWACommand = function(_, arg) seen[#seen + 1] = arg end
        handler("wa")
        handler("wa on")
        handler("wa off")
        assert.are.same({ "", "on", "off" }, seen)
    end)

    it("tolerates surrounding whitespace and capitals", function()
        local seen = {}
        KE.HandleWACommand = function(_, arg) seen[#seen + 1] = arg end
        handler("  WA OFF  ")
        assert.are.same({ "off" }, seen)
    end)

    it("refuses with a message when the slash module never loaded", function()
        local printed = {}
        KE.HandleWACommand = nil
        KE.Print = function(_, msg) printed[#printed + 1] = msg end
        handler("wa off")
        assert.are.same({ "slash commands are not loaded." }, printed)
    end)

end)

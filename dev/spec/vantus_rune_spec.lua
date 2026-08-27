local helpers = require("dev.spec._helpers")

local function loadModule(after)
    local modules = helpers.installAddonShim()
    _G.C_Timer = { After = after or function() end }
    local KE = {
        db = { profile = { VantusRune = {} } },
    }
    helpers.loadModule("Modules/QoL/VantusRune.lua", KE)
    return modules.VantusRune, KE
end

describe("VantusRune guild bank parent", function()
    it("uses the guild view for Baganator's active skin", function()
        local nativeFrame = {}
        local baganatorFrame = {}
        _G.GuildBankFrame = nativeFrame
        _G.Baganator_SingleViewGuildViewFrameelvui = nil
        _G.Baganator_SingleViewGuildViewFrameblizzard = baganatorFrame
        _G.Baganator = {
            API = {
                Skins = {
                    GetCurrentSkin = function() return "blizzard" end,
                },
            },
        }

        local module = loadModule()

        assert.equals(baganatorFrame, module:GetGuildBankParent())
    end)

    it("falls back to the Blizzard guild bank without Baganator", function()
        local nativeFrame = {}
        _G.GuildBankFrame = nativeFrame
        _G.Baganator = nil

        local module = loadModule()

        assert.equals(nativeFrame, module:GetGuildBankParent())
    end)

    it("waits when Baganator's active guild view is not ready", function()
        _G.GuildBankFrame = {}
        _G.Baganator_SingleViewGuildViewFrameblizzard = nil
        _G.Baganator = {
            API = {
                Skins = {
                    GetCurrentSkin = function() return "blizzard" end,
                },
            },
        }

        local module = loadModule()

        assert.is_nil(module:GetGuildBankParent())
    end)

    it("reparents an existing button when the active guild view changes", function()
        local oldParent = {}
        local newParent = {}
        local currentParent = oldParent
        local module = loadModule()
        module.GetGuildBankParent = function() return newParent end
        module.vantusButton = {
            Show = function() end,
            GetParent = function() return currentParent end,
            SetParent = function(_, parent) currentParent = parent end,
            ClearAllPoints = function() end,
            SetPoint = function() end,
        }

        module:CreateGuildBankButton()

        assert.equals(newParent, currentParent)
    end)

    it("reattaches after Baganator swaps frame groups", function()
        local module = loadModule(function(_, callback) callback() end)
        local created = false
        module._isActive = true
        module.db = { Enabled = true }
        module.CreateGuildBankButton = function() created = true end

        module:OnBaganatorFrameGroupSwapped()

        assert.is_true(created)
    end)

    it("does not reattach after the module is disabled", function()
        local pending
        _G.Baganator = {
            CallbackRegistry = {
                UnregisterCallback = function() end,
            },
        }
        local module = loadModule(function(_, callback) pending = callback end)
        local created = false
        module._isActive = true
        module._baganatorCallbackRegistered = true
        module.db = { Enabled = true }
        module.CreateGuildBankButton = function() created = true end
        module.UnregisterAllEvents = function() end

        module:OnBaganatorFrameGroupSwapped()
        module:OnDisable()
        pending()

        assert.is_false(created)
    end)

    it("unregisters the Baganator callback when disabled", function()
        local unregisteredEvent
        local unregisteredOwner
        _G.Baganator = {
            CallbackRegistry = {
                UnregisterCallback = function(_, event, owner)
                    unregisteredEvent = event
                    unregisteredOwner = owner
                end,
            },
        }
        local module = loadModule()
        module._baganatorCallbackRegistered = true
        module.UnregisterAllEvents = function() end

        module:OnDisable()

        assert.equals("FrameGroupSwapped", unregisteredEvent)
        assert.equals(module, unregisteredOwner)
    end)

    it("registers only one Baganator frame-group callback", function()
        local registrations = 0
        local registeredEvent
        local registeredOwner
        _G.Baganator = {
            CallbackRegistry = {
                RegisterCallback = function(_, event, _, owner)
                    registrations = registrations + 1
                    registeredEvent = event
                    registeredOwner = owner
                end,
            },
        }
        local module = loadModule()

        module:RegisterBaganatorCallback()
        module:RegisterBaganatorCallback()

        assert.equals(1, registrations)
        assert.equals("FrameGroupSwapped", registeredEvent)
        assert.equals(module, registeredOwner)
    end)
end)

describe("VantusRune theme refresh", function()
    it("updates the existing button from the current accent", function()
        local module, KE = loadModule()
        local textColor
        local borderColor
        module.vantusButton = {
            text = {
                SetTextColor = function(_, ...)
                    textColor = { ... }
                end,
            },
            border = {
                SetBackdropBorderColor = function(_, ...)
                    borderColor = { ... }
                end,
            },
        }
        KE.Theme = { accent = { 0.1, 0.2, 0.3, 0.4 } }

        module:OnThemeChanged()

        assert.same({ 0.1, 0.2, 0.3, 0.4 }, textColor)
        assert.same({ 0.1, 0.2, 0.3, 0.4 }, borderColor)
    end)
end)

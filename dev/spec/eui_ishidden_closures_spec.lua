-- Tier 2: the isHidden predicate each module hands KE.EUIUnlock:Register
-- (Core/EUIUnlockBridge.lua). The bridge spec drives a predicate it writes
-- itself; these cases capture each module's real closure off a recording
-- KE.EUIUnlock and drive that.
--
-- TotemTracker's frame term is containerFrame, a file-local that only
-- TT:CreateContainer assigns, and that builds the whole totem bar. The case
-- sets the closure's upvalue instead, so nothing but the predicate runs.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")
local L = require("dev.spec._ke_loader")

local function recorder()
    local rec = {}
    rec.Register = function(_, _, opts) rec.isHidden = opts.isHidden end
    return rec
end

local function setUpvalue(fn, name, value)
    local i = 1
    while true do
        local upName = debug.getupvalue(fn, i)
        if not upName then error("no upvalue named " .. name) end
        if upName == name then
            debug.setupvalue(fn, i, value)
            return
        end
        i = i + 1
    end
end

-- Each returns the module's real isHidden, with its frame term present, and
-- the db table it reads Enabled from.
local MODULES = {
    { "TotemTracker", function()
        mock.install({})
        local modules = helpers.installAddonShim()
        local KE = helpers.loadModule("Modules/ClassUtilities/TotemTracker.lua", {})
        KE.EUIUnlock = recorder()
        local TT = modules["TotemTracker"]
        TT.db = {}
        TT:RegisterEditMode()
        setUpvalue(KE.EUIUnlock.isHidden, "containerFrame", {})
        return KE.EUIUnlock.isHidden, TT.db
    end },
    { "Chat", function()
        mock.install({})
        local modules = helpers.installAddonShim()
        local KE = helpers.loadModule("Modules/Skinning/Chat.lua", {})
        KE.EUIUnlock = recorder()
        local CHAT = modules["Chat"]
        CHAT.db = {}
        CHAT.panel = {}
        CHAT:RegisterEditMode()
        return KE.EUIUnlock.isHidden, CHAT.db
    end },
    -- RegWithEditMode returns before the EUI registration unless KE.EditMode
    -- exists.
    { "DamageMeter", function()
        local DM, KE = L.loadDMDock()
        KE.EditMode = { RegisterElement = function() end }
        KE.EUIUnlock = recorder()
        DM.db = {}
        DM.dock = {}
        DM:RegWithEditMode()
        return KE.EUIUnlock.isHidden, DM.db
    end },
}

describe("EUI isHidden closures", function()
    after_each(function()
        mock.reset()
    end)

    for _, m in ipairs(MODULES) do
        it(m[1] .. " hides a disabled module whose frame exists, and shows an enabled one", function()
            local isHidden, db = m[2]()
            db.Enabled = false
            assert.is_true(isHidden())
            db.Enabled = true
            assert.is_false(isHidden())
        end)
    end
end)

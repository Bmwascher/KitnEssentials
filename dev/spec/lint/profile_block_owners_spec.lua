-- Lint: every profile block resolves to the feature that owns it.
--
-- An import or export on a baseline load keeps a block only when its owner is
-- admitted, and an unmapped block's owner is the module of its own name
-- (KE:ProfileBlockOwner, Core/Availability.lua). A block named apart from its
-- module would be dropped on Forever even after that module is admitted, so
-- every Defaults block, and every sub-block of a nested container, has to be
-- a core key, a mapped key or a module's name.
local lfs = require("lfs")
local helpers = require("dev.spec._helpers")

local function readFile(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local function walkLuaFiles(dir, acc)
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local path = dir .. "/" .. entry
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                walkLuaFiles(path, acc)
            elseif mode == "file" and entry:match("%.lua$") then
                acc[#acc + 1] = path
            end
        end
    end
    return acc
end

-- Module names as NewModule and the aura header factory register them.
local function ModuleNames()
    local names = {}
    for _, path in ipairs(walkLuaFiles("Modules", {})) do
        local text = readFile(path)
        for name in text:gmatch('NewModule%(%s*"([%w_]+)"') do names[name] = true end
        for name in text:gmatch('moduleName%s*=%s*"([%w_]+)"') do names[name] = true end
    end
    return names
end

describe("profile block owners", function()
    it("resolves every Defaults block and nested sub-block to a core key, a mapped owner or a module", function()
        local KE = helpers.loadModule("Core/Availability.lua", {})
        helpers.loadModule("Core/Defaults.lua", KE)
        local modules = ModuleNames()
        assert.is_true(modules.Automation == true and modules.CVars == true, "positive control: module names were found")
        local unresolved = {}
        local function check(key)
            local kind, owner, mapped = KE:ProfileBlockOwner(key)
            if kind == "feature" and not mapped and not modules[owner] then
                unresolved[#unresolved + 1] = key
            end
        end
        for key, block in pairs(KE:GetDefaultDB().profile) do
            if KE:ProfileBlockOwner(key) == "nested" then
                for subKey in pairs(block) do check(subKey) end
            else
                check(key)
            end
        end
        table.sort(unresolved)
        assert.same({}, unresolved)
    end)
end)

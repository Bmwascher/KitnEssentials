-- Smoke: every shipped source file must compile (loadfile) without a syntax
-- error. This is the cheap, env-free safety net — it catches "this file is
-- broken" across the whole addon in one pass, with per-file granularity so a
-- failure names the offending file. It does NOT execute the files (that needs
-- the full WoW environment); static correctness of globals is luacheck's job.
local lfs = require("lfs")

local ROOTS = { "Core", "Modules", "GUI" }

local function walk(dir, acc)
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local path = dir .. "/" .. entry
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                walk(path, acc)
            elseif mode == "file" and entry:match("%.lua$") then
                acc[#acc + 1] = path
            end
        end
    end
    return acc
end

describe("source files compile (loadfile smoke)", function()
    local files = {}
    for _, root in ipairs(ROOTS) do
        if lfs.attributes(root, "mode") == "directory" then
            walk(root, files)
        end
    end
    table.sort(files)

    it("found a non-trivial number of source files", function()
        assert.is_true(#files > 50, "expected >50 lua files, found " .. #files)
    end)

    for _, path in ipairs(files) do
        it("compiles " .. path, function()
            local chunk, err = loadfile(path)
            assert.is_function(chunk, "syntax error in " .. path .. ": " .. tostring(err))
        end)
    end
end)

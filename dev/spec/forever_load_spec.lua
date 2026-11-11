-- dev/spec/forever_load_spec.lua
local L = dofile("dev/scripts/_forever_load.lua")

describe("Forever load rules (dev/scripts/_forever_load.lua)", function()
    it("admits a gate naming camelot or mainline and refuses on either exclusion", function()
        local cases = {
            { "File.lua", true },
            { "File.lua [AllowLoadGameType camelot]", true },
            { "File.lua [AllowLoadGameType wrath, cata, mainline]", true },
            { "File.lua [AllowLoadGameType standard]", false },
            { "File.lua [AllowLoadGameType classic]", false },
            { "File.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]", false },
            { "File.lua [ExcludeLoadGameType classic]", true },
            { "File.lua [ExcludeLoadGameType mainline]", false },
        }
        for _, case in ipairs(cases) do
            assert.equals(case[2], L.gateAllows(case[1]), case[1])
        end
    end)

    it("decides from the header whether the addon loads in game", function()
        local cases = {
            { "## Title: A\nFile.lua", true },
            { "## AllowLoadGameType: standard, wowlabs\nFile.lua", false },
            { "## AllowLoadGameType: classic, camelot\nFile.lua", true },
            { "## ExcludeLoadGameType: camelot\nFile.lua", false },
            { "## AllowLoad: Glue\nFile.lua", false },
            { "## AllowLoad: game [AllowLoadGameType classic]\nFile.lua", true },
            { "## AllowLoad: glue [AllowLoadGameType mainline]\nFile.lua", false },
        }
        for _, case in ipairs(cases) do
            assert.equals(case[2], L.headerAllows(case[1]), case[1])
        end
    end)

    it("lists the loaded lines in order with the folder tokens resolved", function()
        local toc = table.concat({
            "## Title: A",
            "Shared\\Base.lua",
            "[Family]\\Util.lua [AllowLoadGameType mainline]",
            "[Family]\\Skipped.lua\t[AllowLoadGameType mainline] [ExcludeLoadGameType camelot]",
            "Classic\\Util.lua [AllowLoadGameType classic]",
            "[Game]\\Util.lua [AllowLoadGameType camelot]",
        }, "\r\n")
        assert.same({ "Shared\\Base.lua", "Mainline\\Util.lua", "Camelot\\Util.lua" }, L.tocFiles(toc))
    end)
end)

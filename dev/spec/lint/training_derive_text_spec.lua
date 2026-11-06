-- The script's input tables are read as text only. These two files turn that
-- text into tables, so neither may hold a call that could run any of it.
local PATHS = { "dev/scripts/_lua_text.lua", "dev/scripts/_training_derive.lua" }
local WORDS = { "load", "loadstring", "loadfile", "dofile" }

describe("What's Training text reading", function()
    it("holds no call that runs code", function()
        for _, path in ipairs(PATHS) do
            local file = assert(io.open(path, "rb"))
            local text = file:read("*a")
            file:close()
            for _, word in ipairs(WORDS) do
                assert.is_nil(text:find("%f[%w_]" .. word .. "%f[^%w_]"), path .. " holds " .. word)
            end
        end
    end)
end)

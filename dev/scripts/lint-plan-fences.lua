-- Lint every fenced Lua block in a markdown plan before the plan freezes.
-- Read-only review lanes cannot run linters; an identical shadowing defect
-- once survived 24 review rounds inside a plan's fenced code.
--
--   lua dev/scripts/lint-plan-fences.lua <plan.md> [more.md ...]
--
-- Exit 0: every block clean or skipped as a fragment. Exit 1: a syntax
-- error (checked with THIS Lua 5.1 parser via loadstring, which luacheck's
-- multi-version parser cannot do), a luacheck warning/error, or an
-- unterminated fence. Requires luacheck on PATH (PowerShell — the hererocks
-- tree is not on the Git Bash PATH). Which fences are fragments:
-- _plan_fences.lua.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local PF = dofile(_dir .. "_plan_fences.lua")

-- Table address gives per-process entropy os.time/os.clock cannot.
local run_id = tostring(os.time()) .. "_" .. (tostring({}):match("x(%x+)$") or "0")

-- Runs only on a block that loads; PF.triage has checked its syntax.
local function luacheck_block(block, index, plan)
    local tmp = os.getenv("TEMP") or os.getenv("TMP") or "."
    local snippet = string.format("%s\\plan-fence-%s-%d-%d.lua", tmp, run_id, index, block.first)
    local out = io.open(snippet, "w")
    if not out then return false, "cannot write " .. snippet end
    local wrote = out:write(block.code, "\n")
    local closed = out:close()
    if not wrote or not closed then
        os.remove(snippet)
        return false, "failed writing " .. snippet .. " (disk full?)"
    end
    -- Plan snippets reference project globals freely; syntax, shadowing,
    -- unused/undefined LOCALS are the defect classes this exists for, so
    -- global warnings (11x) are silenced — a misspelled global read is the
    -- accepted blind spot of that trade.
    -- A fence with no target path is a busted spec when it calls describe( or
    -- it(, and gets busted's globals the way .luacheckrc gives them to dev/spec.
    local std = ""
    for line in (block.code .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^%s*describe%s*%(") or line:match("^%s*it%s*%(") then
            std = " --std lua51+busted"
            break
        end
    end
    local cmd = string.format('luacheck "%s" --codes --no-color --ignore 11%s 2>&1', snippet, std)
    local pipe = io.popen(cmd)
    local report = pipe:read("*a")
    pipe:close()
    os.remove(snippet)
    -- Lua 5.1 pipe:close() cannot report the exit code — parse luacheck's own
    -- totals line, and treat a missing totals line (luacheck absent, crashed)
    -- as a failure rather than a pass.
    local warnings, errors = report:match("Total:%s*(%d+)%s+warnings?%s*/%s*(%d+)%s+errors?")
    if not warnings then
        return false, "luacheck produced no totals line - is it on PATH (PowerShell)?\n" .. report
    end
    if tonumber(warnings) == 0 and tonumber(errors) == 0 then return true end
    return false, (report:gsub(snippet:gsub("[%-%.%\\]", "%%%1"), string.format("%s:fence@%d", plan, block.first)))
end

local args = { ... }
if #args == 0 then
    io.stderr:write("usage: lua dev/scripts/lint-plan-fences.lua <plan.md> [more.md ...]\n")
    os.exit(2)
end

local dirty = false
for _, plan in ipairs(args) do
    local blocks, err = PF.collect_file(plan)
    if not blocks then
        io.stderr:write(string.format("[plan-fences] %s: %s\n", plan, tostring(err)))
        os.exit(err and tostring(err):match("unterminated") and 1 or 2)
    end
    if #blocks == 0 then
        print(string.format("[plan-fences] %s: no ```lua fences", plan))
    end
    for i, block in ipairs(blocks) do
        local where = string.format("[plan-fences] %s lines %d-%d", plan, block.first, block.last)
        local status, syntax_err = PF.triage(block)
        if status == "anchor" then
            print(where .. ": fragment, skipped (anchor)")
        elseif status == "fragment" then
            print(where .. ": fragment, skipped")
        else
            local ok, report
            if status == "syntax" then
                ok, report = false, "Lua 5.1 syntax error: " .. tostring(syntax_err)
            else
                ok, report = luacheck_block(block, i, plan)
            end
            if ok then
                print(where .. ": clean")
            else
                dirty = true
                print(where .. ": FINDINGS")
                io.write(report or "", "\n")
            end
        end
    end
end
os.exit(dirty and 1 or 0)

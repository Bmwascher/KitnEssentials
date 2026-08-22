-- Lint every fenced Lua block in a markdown plan before the plan freezes.
-- Read-only review lanes cannot run linters; an identical shadowing defect
-- once survived 24 review rounds inside a plan's fenced code.
--
--   lua dev/scripts/lint-plan-fences.lua <plan.md> [more.md ...]
--
-- Exit 0: every block clean. Exit 1: a syntax error (checked with THIS Lua
-- 5.1 parser via loadstring, which luacheck's multi-version parser cannot
-- do), a luacheck warning/error, or an unterminated fence. Requires luacheck
-- on PATH (PowerShell — the hererocks tree is not on the Git Bash PATH).

local function collect_blocks(path)
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local blocks, current, start_line = {}, nil, nil
    local n = 0
    for line in f:lines() do
        n = n + 1
        if current then
            -- A closing fence is backticks only — "```lua" here would OPEN a
            -- fence in markdown, and treating it as a close would silently
            -- truncate the block under lint.
            if line:match("^%s*```+%s*$") then
                blocks[#blocks + 1] = {
                    first = start_line, last = n, code = table.concat(current, "\n"),
                }
                current = nil
            else
                current[#current + 1] = line
            end
        elseif line:match("^%s*```lua%s*$") then
            current, start_line = {}, n + 1
        end
    end
    f:close()
    if current then
        return nil, string.format("unterminated ```lua fence opened at line %d", start_line - 1)
    end
    return blocks
end

-- Table address gives per-process entropy os.time/os.clock cannot.
local run_id = tostring(os.time()) .. "_" .. (tostring({}):match("x(%x+)$") or "0")

local function lint_block(block, index, plan)
    -- Exact 5.1 syntax first: luacheck's parser accepts newer-Lua syntax
    -- (e.g. `//`) that WoW's 5.1 runtime rejects.
    local chunk, syntax_err = loadstring(block.code, "fence")
    if not chunk then
        return false, "Lua 5.1 syntax error: " .. tostring(syntax_err)
    end
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
    local cmd = string.format('luacheck "%s" --codes --no-color --ignore 11 2>&1', snippet)
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
    local blocks, err = collect_blocks(plan)
    if not blocks then
        io.stderr:write(string.format("[plan-fences] %s: %s\n", plan, tostring(err)))
        os.exit(err and tostring(err):match("unterminated") and 1 or 2)
    end
    if #blocks == 0 then
        print(string.format("[plan-fences] %s: no ```lua fences", plan))
    end
    for i, block in ipairs(blocks) do
        local ok, report = lint_block(block, i, plan)
        if ok then
            print(string.format("[plan-fences] %s lines %d-%d: clean", plan, block.first, block.last))
        else
            dirty = true
            print(string.format("[plan-fences] %s lines %d-%d: FINDINGS", plan, block.first, block.last))
            io.write(report or "", "\n")
        end
    end
end
os.exit(dirty and 1 or 0)

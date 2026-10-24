-- _plan_fences.lua — the fence collector and fragment rule behind
-- lint-plan-fences.lua, kept apart so a spec can load it with dofile.
--
-- A task list quotes an anchor (lines that already exist in a file) and
-- then the new text. An anchor fence is never linted. The fence right after
-- one is linted, and only a failed load there reads as a fragment (a table
-- field, an elseif arm) instead of a syntax error.

local PF = {}

local function is_anchor_prose(line)
    return line ~= nil and line:lower():match("anchor:%s*$") ~= nil
end

-- text -> array of { first, last, code, kind }, or nil and the
-- unterminated-fence message. kind is "anchor", "new_text" or "full".
function PF.collect(text)
    local blocks, current, start_line, kind = {}, nil, nil, nil
    local prose, prev_anchor = nil, false
    local n = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        line = line:gsub("\r$", "")
        if current then
            -- A closing fence is backticks only — "```lua" here would OPEN a
            -- fence in markdown, and treating it as a close would silently
            -- truncate the block under lint.
            if line:match("^%s*```+%s*$") then
                blocks[#blocks + 1] = {
                    first = start_line, last = n, code = table.concat(current, "\n"), kind = kind,
                }
                prev_anchor = (kind == "anchor")
                current, prose = nil, nil
            else
                current[#current + 1] = line
            end
        elseif line:match("^%s*```lua%s*$") then
            if is_anchor_prose(prose) then
                kind = "anchor"
            elseif prev_anchor then
                kind = "new_text"
            else
                kind = "full"
            end
            current, start_line = {}, n + 1
        elseif line:match("%S") then
            -- Any other fence between an anchor and this one breaks the pair.
            if line:match("^%s*```") then prev_anchor = false end
            prose = line
        end
    end
    if current then
        return nil, string.format("unterminated ```lua fence opened at line %d", start_line - 1)
    end
    return blocks
end

function PF.collect_file(path)
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local text = f:read("*a")
    f:close()
    return PF.collect(text)
end

-- block -> "anchor" | "fragment" | "lint" | "syntax", err. loadstring is the
-- exact Lua 5.1 parser: luacheck's accepts newer-Lua syntax (e.g. `//`) that
-- WoW's 5.1 runtime rejects.
function PF.triage(block)
    if block.kind == "anchor" then return "anchor" end
    local chunk, err = loadstring(block.code, "fence")
    if chunk then return "lint" end
    if block.kind == "new_text" then return "fragment" end
    return "syntax", err
end

return PF

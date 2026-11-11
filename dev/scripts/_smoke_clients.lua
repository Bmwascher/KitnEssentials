-- _smoke_clients.lua: pure classification for smoke-clients.lua. Decides, for
-- one changed path, which game client loads it. Runs under Lua 5.1 and 5.4.

local S = {}

local NOT_SHIPPED_DIRS = { "dev/", ".claude/", ".agents/", ".codex/", ".github/", ".vscode/", "References/" }

local function notShipped(path)
    for _, dir in ipairs(NOT_SHIPPED_DIRS) do
        if path:sub(1, #dir) == dir then return true end
    end
    -- root dotfiles and root docs are packaging or repo files, never loaded
    if not path:find("/", 1, true) and (path:sub(1, 1) == "." or path:match("%.md$")) then
        return true
    end
    return false
end

-- retail and forever are sets of repo-relative paths from load-list.lua.
-- Returns "both", "retail", "forever", "none" (not shipped) or "unlisted"
-- (shipped, but in neither load list: an asset, a toc or a deleted file).
function S.classify(path, retail, forever)
    if retail[path] and forever[path] then return "both" end
    if retail[path] then return "retail" end
    if forever[path] then return "forever" end
    if notShipped(path) then return "none" end
    return "unlisted"
end

-- classes is a list of classify results. An unlisted file cannot be placed,
-- so it counts for both clients.
function S.summary(classes)
    local retail, forever = false, false
    for _, class in ipairs(classes) do
        if class == "both" or class == "unlisted" then retail, forever = true, true end
        if class == "retail" then retail = true end
        if class == "forever" then forever = true end
    end
    if retail and forever then return "Retail and Forever" end
    if retail then return "Retail only" end
    if forever then return "Forever only" end
    return "neither client (no shipped file changed)"
end

return S

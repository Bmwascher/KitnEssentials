-- ╔══════════════════════════════════════════════════════════╗
-- ║  DataBuild.lua                                           ║
-- ║  Purpose: Turns a table's stored source into the table   ║
-- ║           and releases the text. Loads with this folder, ║
-- ║           so only a module that needs data ever reads it.║
-- ╚══════════════════════════════════════════════════════════╝

local KE = KitnEssentials:GetNamespace()

local loadstring = loadstring
local pcall = pcall
local type = type

local MISSING = "a data file is missing"
local UNREADABLE = "a data file could not be read"

local built = {}

-- A failed build keeps its text and raises nothing; the caller refuses.
function KE.BuildData(name)
    if built[name] then return built[name] end
    local sources = KE.DataSources
    local source = sources and sources[name]
    if type(source) ~= "string" then return nil, MISSING end
    local compiled, chunk = pcall(loadstring, source, "=" .. name)
    if not compiled or not chunk then return nil, UNREADABLE end
    local ran, data = pcall(chunk)
    if not ran or type(data) ~= "table" then return nil, UNREADABLE end
    built[name] = data
    sources[name] = nil
    return data
end

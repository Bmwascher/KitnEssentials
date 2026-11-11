-- update-api-reference.lua — update one local WoW API reference clone and
-- report API changes since the last update that intersect KE's used surface.
--
--   lua dev/scripts/update-api-reference.lua                (from repo root)
--   lua dev/scripts/update-api-reference.lua --report-only  (no fetch, no writes)
--   lua dev/scripts/update-api-reference.lua --seed         (no fetch; write baseline)
--   lua dev/scripts/update-api-reference.lua --client forever [--report-only | --seed]
--
-- Snapshot-diff (WowDoc changes_apidoc keying); exit 1 iff BREAKING-USED
-- findings; snapshots only rewritten after a fully successful parse+diff.
--
-- The default client is Retail: the `.wow-api-reference` clone, every KE
-- source file and the C-side dump. `--client forever` runs the same watch on
-- the Forever clone beside it, with its own snapshot, against only the files
-- the Forever client loads; the C-side dump is not tracked there. Both modes
-- locate the clones through the `.wow-api-reference` junction, so the Forever
-- mode needs that junction too, though it reads nothing in the Retail clone.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local P = dofile(_dir .. "_apidocs_parser.lua")
local C = dofile(_dir .. "_api_drift_core.lua")

-- drift-check allowlist: C-SIDE entries that are missing_ok members get a
-- cross-reference annotation (spec: "so the two tools cross-reference")
local allowOk, allow = pcall(dofile, _dir .. "luacheckrc-drift-allow.lua")
local missingOk = (allowOk and type(allow) == "table" and allow.missing_ok) or {}

local MODE, FOREVER = "update", false
for i = 1, #arg do
    if arg[i] == "--report-only" then MODE = "report" end
    if arg[i] == "--seed" then MODE = "seed" end
    if arg[i] == "--client" then
        assert(arg[i + 1] == "retail" or arg[i + 1] == "forever", "--client takes retail or forever")
        FOREVER = arg[i + 1] == "forever"
    end
end

local ROOT = P.resolveRepoRoot(arg[0])

-- 5.1/5.4 compat: os.execute returns number (5.1) or bool (5.2+)
local function execOk(cmd)
    local r = os.execute(cmd)
    return r == true or r == 0
end

local function popenLine(cmd)
    local p = io.popen(cmd)
    if not p then return nil end
    local line = p:read("*l")
    p:close()
    return line
end

local clones = assert(P.referenceClones(ROOT),
    ".wow-api-reference is not a git checkout — see the memory note for setup")
local REF = FOREVER and clones.forever or clones.retail
local BRANCH = FOREVER and "forever" or "live"
local BIR = clones.parent .. "\\blizzard-interface-resources"
local SNAPDIR = clones.parent .. "\\api-drift-snapshots"
local DOCS_SNAPSHOT = FOREVER and "docs-snapshot-forever.lua" or "docs-snapshot.lua"
local DOCS = REF .. "\\Interface\\AddOns\\Blizzard_APIDocumentationGenerated"
local ADDONS = REF .. "\\Interface\\AddOns"
assert(execOk('git -C "' .. REF .. '" rev-parse --git-dir >nul 2>nul'),
    "no reference clone at " .. REF)

-- ---- step 1-2: fetch/merge (update mode only) ---------------------------
if MODE == "update" then
    print("[update] fetching " .. REF .. " ...")
    assert(execOk('git -C "' .. REF .. '" fetch origin ' .. BRANCH),
        "git fetch failed (offline?) — no state touched; retry or run --report-only")
    assert(execOk('git -C "' .. REF .. '" merge --ff-only origin/' .. BRANCH),
        "ff-only merge failed (diverged clone) — fix manually: git -C \"" .. REF
        .. "\" status")
end
if MODE == "update" and not FOREVER then
    if not execOk('git -C "' .. BIR .. '" rev-parse --git-dir >nul 2>nul') then
        print("[update] cloning BlizzardInterfaceResources (first run) ...")
        if not execOk('git clone --depth 1 --branch live '
            .. 'https://github.com/Ketho/BlizzardInterfaceResources "' .. BIR .. '"') then
            print("NOTICE: BlizzardInterfaceResources clone failed — C-SIDE section will be empty")
        end
    else
        if not execOk('git -C "' .. BIR .. '" fetch --depth 1 origin live') or
           not execOk('git -C "' .. BIR .. '" reset --hard origin/live >nul') then
            print("NOTICE: BlizzardInterfaceResources update failed — using its last state")
        end
    end
end

-- ---- step 3: parse current state -----------------------------------------
local version = P.readBuild(REF)
local docRes = P.collectDocTables(DOCS)
assert(docRes.filesRead >= 500,
    ("only %d API-docs files read (expected >= 500) — reference damaged; snapshots untouched")
    :format(docRes.filesRead))
local flat = C.flattenDocs(docRes.tables)

local dirs = P.listDirs(ADDONS)
table.sort(dirs)

local bir = { globals = {}, events = {}, cvars = {}, frames = {}, mixins = {} }
local birFilesParsed = 0
local birFileMap = { GlobalAPI = "globals", Events = "events", CVars = "cvars",
                     Frames = "frames", Mixins = "mixins" }
for fname, key in pairs(birFileMap) do
    local src = not FOREVER and P.readAll(BIR .. "\\Resources\\" .. fname .. ".lua")
    if src then
        bir[key] = C.parseBIRSource(src, P.loadSandboxed)
        birFilesParsed = birFilesParsed + 1
    end
end
local birVersion = popenLine('git -C "' .. BIR .. '" log -1 --format=%s 2>nul') or "absent"

-- ---- step 4: used surface -------------------------------------------------
local used = C.newUsedSurface()
local keFiles = {}
if FOREVER then
    for _, rel in ipairs(P.loadedLuaFiles(ROOT, "camelot", arg[-1])) do
        keFiles[#keFiles + 1] = ROOT .. "\\" .. rel:gsub("/", "\\")
    end
else
    for _, sub in ipairs({ "Core", "Modules", "GUI", "KitnEssentials_Options" }) do
        for _, f in ipairs(P.listFiles(ROOT .. "\\" .. sub, "*.lua")) do keFiles[#keFiles + 1] = f end
    end
end
local nKeFiles = 0
for _, f in ipairs(keFiles) do
    local src = P.readAll(f)
    if src then
        nKeFiles = nKeFiles + 1
        C.harvestUsedFromSource(src, used)
    end
end
assert(nKeFiles >= 100, ("only %d KE files harvested — run from the repo root"):format(nKeFiles))
-- .luacheckrc names every global KE uses on either client, so it would widen
-- the Forever surface past the files Forever loads.
local rcEnv = { files = {} }
local rcSrc = not FOREVER and P.readAll(ROOT .. "\\.luacheckrc")
if rcSrc then
    local chunk = P.loadSandboxed(rcSrc, "@.luacheckrc", rcEnv)
    if chunk then pcall(chunk) end
    C.addLuacheckrcNames(rcEnv.globals, rcEnv.read_globals, used)
end
local pred = C.usedPredicates(used)

-- ---- step 5: snapshots ------------------------------------------------------
local function snapPath(name) return SNAPDIR .. "\\" .. name end
local function writeSnapshot(name, snap)
    execOk('mkdir "' .. SNAPDIR .. '" 2>nul')
    local tmp = snapPath(name .. ".new")
    local fh = assert(io.open(tmp, "w"))
    fh:write(C.serializeSnapshot(snap))
    fh:close()
    os.remove(snapPath(name))
    assert(os.rename(tmp, snapPath(name)), "snapshot rename failed: " .. name)
end

local newDocsSnap = { build = version, date = os.date("%Y-%m-%d %H:%M"),
    functions = flat.functions, events = flat.events, enums = flat.enums, dirs = dirs }
local birSets = {}
for _, k in ipairs({ "globals", "events", "cvars", "frames", "mixins" }) do
    birSets[k] = bir[k]
end
local newBirSnap = { build = birVersion, date = newDocsSnap.date, bir = birSets }

local function writeSnapshots()
    writeSnapshot(DOCS_SNAPSHOT, newDocsSnap)
    if not FOREVER then writeSnapshot("bir-snapshot.lua", newBirSnap) end
end

local oldSrc = P.readAll(snapPath(DOCS_SNAPSHOT))
local oldSnap = oldSrc and C.loadSnapshotFromString(oldSrc, P.loadSandboxed)
local oldBirSrc = not FOREVER and P.readAll(snapPath("bir-snapshot.lua"))
local oldBir = oldBirSrc and C.loadSnapshotFromString(oldBirSrc, P.loadSandboxed)

if MODE == "seed" or not oldSnap then
    if MODE == "report" then
        print("api-drift: no baseline snapshot at " .. SNAPDIR)
        print("(--report-only never writes state; run without flags, or --seed)")
        os.exit(0)
    end
    writeSnapshots()
    print(("api-drift: baseline seeded at build %s (%d functions, %d events, %d enums)")
        :format(version, P.count(flat.functions), P.count(flat.events), P.count(flat.enums)))
    print("run again after the next reference update to get a report")
    os.exit(0)
end

-- ---- step 6: diff + filter ----------------------------------------------------
local dFn = C.diffMaps(oldSnap.functions or {}, flat.functions)
local dEv = C.diffMaps(oldSnap.events or {}, flat.events)
local dEn = C.diffMaps(oldSnap.enums or {}, flat.enums)

local breaking = {}
local function addBreaking(list, pred_, label)
    local r = C.filterUsed(list, pred_)
    for _, k in ipairs(r.hit) do breaking[#breaking + 1] = k .. "  " .. label end
    return r
end
addBreaking(dFn.removed, pred.fn, "REMOVED")
addBreaking(dFn.changed, pred.fn, "CHANGED (signature/secret flags — see docs)")
addBreaking(dEv.removed, pred.event, "event REMOVED")
addBreaking(dEv.changed, pred.event, "event payload CHANGED")
addBreaking(dEn.removed, pred.enum, "enum member REMOVED")
for _, k in ipairs(C.filterUsed(dEn.changed, pred.enum).hit) do
    breaking[#breaking + 1] = ("%s  %s -> %s"):format(k,
        tostring((oldSnap.enums or {})[k]), tostring(flat.enums[k]))
end

local cside = {}
local csideGating = 0
-- birFilesParsed == 0 must short-circuit: diffing a real old snapshot against
-- empty parsed sets would report every known name as falsely REMOVED
-- Forever tracks no C-side dump and gets no notice line here: every cside
-- line counts as a used-surface hit in [FYI].
if not FOREVER and birFilesParsed == 0 then
    cside[#cside + 1] = "NOTICE: BlizzardInterfaceResources unavailable — section skipped"
elseif oldBir and oldBir.bir then
    for _, k in ipairs({ "globals", "events", "cvars", "frames", "mixins" }) do
        local d = C.diffMaps(oldBir.bir[k] or {}, birSets[k] or {})
        local p2 = (k == "cvars") and pred.cvar or (k == "events") and pred.event or pred.name
        for _, sym in ipairs(C.filterUsed(d.removed, p2).hit) do
            local note = missingOk[sym]
                and ("  (drift-check allowlisted: " .. missingOk[sym] .. ")") or ""
            if not missingOk[sym] then csideGating = csideGating + 1 end
            cside[#cside + 1] = ("%s  REMOVED from %s dump%s"):format(sym, k, note)
        end
    end
end

local additions = {}
for _, k in ipairs(C.filterUsed(dFn.added, pred.fnNsAddition).hit) do
    additions[#additions + 1] = k .. "  added"
end
local oldDirSet, newDirSet = {}, {}
for _, d in ipairs(oldSnap.dirs or {}) do oldDirSet[d] = true end
for _, d in ipairs(dirs) do newDirSet[d] = true end
for d in pairs(newDirSet) do
    if not oldDirSet[d] and d:match("^Blizzard_Deprecated") then
        additions[#additions + 1] = d .. "  NEW deprecation shim addon"
    end
end
table.sort(additions)

local fyiTotal = #dFn.added + #dFn.removed + #dFn.changed
    + #dEv.added + #dEv.removed + #dEv.changed
    + #dEn.added + #dEn.removed + #dEn.changed
local fyiUsed = #breaking + #cside + #additions

local buildNum = version:match("%.(%d+)$") or version
local patch = version:match("^(%d+%.%d+%.%d+)") or version
local lines, code = C.renderReport({
    client = FOREVER and "Forever, C-side not tracked" or nil,
    oldBuild = oldSnap.build or "?", newBuild = version,
    oldDate = oldSnap.date or "?", date = newDocsSnap.date,
    sections = { breaking = breaking, cside = cside, additions = additions },
    csideGating = csideGating,
    fyiTotal = fyiTotal, fyiUsed = fyiUsed,
    -- both sites index Retail builds only
    links = FOREVER and {} or {
        "https://www.townlong-yak.com/framexml/" .. buildNum,
        "https://warcraft.wiki.gg/wiki/Patch_" .. patch .. "/API_changes",
    },
})
for _, l in ipairs(lines) do print(l) end

-- ---- step 7-8: persist (not in report mode), exit ---------------------------
if MODE == "update" then writeSnapshots() end
os.exit(code)

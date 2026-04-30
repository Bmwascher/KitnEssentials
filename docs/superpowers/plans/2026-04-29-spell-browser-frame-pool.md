# Spell Browser Frame Pool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the per-click frame leak in the DungeonTimers spell browser by extracting a reusable `KE.FramePool` primitive and adopting it for spell rows, boss header rows, and separators.

**Architecture:** Blizzard-style frame-pool pattern — pool exposes `Acquire(parent)` and `ReleaseAll()`, kits live on a hidden holder when idle. Per-kit-type pools (3 instances in spell browser). No changes to ContentArea; pool lifecycle is local to the adopter file.

**Tech Stack:** Lua 5.1 (WoW 12.0), AceAddon-3.0, wowlua-ls (type checking), luacheck (linting), in-game `/reload` + BugSack (runtime verification).

**Spec:** [docs/superpowers/specs/2026-04-29-spell-browser-frame-pool-design.md](../specs/2026-04-29-spell-browser-frame-pool-design.md)

---

## Branch and isolation

Working on `kicktracker-wip`. Pre-existing checkpoints serve as revert points:
- `765f2d0` — DungeonTimers GC churn fixes (this session)
- `b63f54e` — KickTracker WIP (pre-existing)
- `a963461` — Spec doc

If anything in this plan goes wrong: `git revert <sha>` of the relevant task commit. No worktree needed; isolation is per-commit.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `Core/FramePool.lua` | Create | The reusable pool primitive: `KE.FramePool:New(factory, resetter?)` returning an object with `Acquire(parent)` and `ReleaseAll()`. Owns the hidden holder Frame and the kit array. |
| `Core/Core.xml` | Modify (1 line) | Add `<Script file="FramePool.lua"/>` after `Widgets.lua` so the primitive is loaded before any GUI widget tries to use it. |
| `GUI/GUIWidgets/GUI-SpellBrowserCard.lua` | Refactor in place | Add 3 factories (`CreateSpellRowKit`, `CreateBossHeaderKit`, `CreateSeparatorKit`), 3 configure functions (`ConfigureSpellRow`, `ConfigureBossHeader`, `ConfigureSeparator`), 3 pool instances at file scope, and rewrite `CreateSpellBrowserCard` body to use `pool:ReleaseAll()` + `pool:Acquire(card.content)` instead of `CreateFrame`. |
| `Annotations/KE.lua` | Modify | Add `---@class KE.FramePool` declaration with method signatures so wowlua-ls knows the type. |

Tasks below correspond to logical commit boundaries.

---

## Task 1: Create the FramePool primitive

**Files:**
- Create: `Core/FramePool.lua`
- Modify: `Core/Core.xml:9` (add line after `Widgets.lua`)

- [ ] **Step 1: Create `Core/FramePool.lua`**

Write the full file:

```lua
-- ╔══════════════════════════════════════════════════════════╗
-- ║  FramePool.lua                                           ║
-- ║  Module: KE.FramePool                                    ║
-- ║  Purpose: Reusable typed frame pool. Lets GUI code that  ║
-- ║           rebuilds frames per-render reuse them instead  ║
-- ║           of leaking via SetParent(nil) -> UIParent      ║
-- ║           orphaning.                                     ║
-- ║                                                          ║
-- ║  Pattern matches Blizzard's FramePool / FramePoolMixin:  ║
-- ║  consumer calls ReleaseAll() at top of render to mark    ║
-- ║  every kit idle, then Acquire(parent) per kit needed.    ║
-- ║  Surplus kits stay hidden in the pool's holder; new      ║
-- ║  demand grows the pool. No individual Release().         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CreateFrame = CreateFrame
local UIParent = UIParent

---@class KE.FramePool
---@field _factory  fun(holder: Frame): table
---@field _resetter fun(kit: table)?
---@field _holder   Frame
---@field _kits     table[]
---@field _activeCount integer
local FramePool = {}
FramePool.__index = FramePool

--- Create a new typed pool.
---@param factory  fun(holder: Frame): table  -- creates one kit when pool is empty
---@param resetter fun(kit: table)?           -- optional; called on each kit during ReleaseAll
---@return KE.FramePool
function FramePool:New(factory, resetter)
    local instance = setmetatable({}, FramePool)
    instance._factory = factory
    instance._resetter = resetter
    instance._holder = CreateFrame("Frame", nil, UIParent)
    instance._holder:Hide()
    instance._kits = {}
    instance._activeCount = 0
    return instance
end

--- Borrow a kit, reparenting it to `parent`. Grows the pool on demand.
--- O(1) amortized — index-based lookup, no table search.
---@param parent Frame
---@return table kit
function FramePool:Acquire(parent)
    self._activeCount = self._activeCount + 1
    local kit = self._kits[self._activeCount]
    if not kit then
        kit = self._factory(self._holder)
        self._kits[self._activeCount] = kit
    end
    -- Kits expose their root Frame as kit.row by convention. Other sub-frames
    -- ride along since they're descendants of the root.
    local root = kit.row or kit.frame or kit
    root:SetParent(parent)
    root:Show()
    return kit
end

--- Mark every active kit as idle. Reparents kits back to the pool's hidden
--- holder (so subsequent ClearContent passes don't orphan them) and calls
--- the resetter on each. Always called at the top of a render before any
--- Acquire — there is no individual Release.
function FramePool:ReleaseAll()
    for i = 1, self._activeCount do
        local kit = self._kits[i]
        local root = kit.row or kit.frame or kit
        root:SetParent(self._holder)
        root:Hide()
        if self._resetter then
            self._resetter(kit)
        end
    end
    self._activeCount = 0
end

KE.FramePool = FramePool
```

- [ ] **Step 2: Register the file in `Core/Core.xml`**

Modify `Core/Core.xml`. Find the line:

```xml
    <Script file="Widgets.lua" />
```

Insert immediately after it:

```xml
    <Script file="FramePool.lua" />
```

The full Core.xml block should now read:

```xml
    <Script file="CustomOutline.lua" />
    <Script file="Widgets.lua" />
    <Script file="FramePool.lua" />
    <Script file="Defaults.lua"/>
    <Script file="Globals.lua" />
```

- [ ] **Step 3: Lint clean**

Run from project root:

```bash
luacheck Core/FramePool.lua --config .luacheckrc
```

**Expected output:** `Total: 0 warnings / 0 errors in 1 file`

- [ ] **Step 4: wowlua-ls clean**

Open `Core/FramePool.lua` in VS Code. Check the Problems panel for that file.

**Expected:** 0 problems on that file. (You may need to reload the wowlua-ls language server first via `Ctrl+Shift+P` → "Developer: Reload Window" if the new file isn't picked up immediately.)

- [ ] **Step 5: Smoke load in WoW**

In-game: `/reload`. Open BugSack. Run:

```
/run print(KitnEssentials.FramePool ~= nil)
```

**Expected:** prints `true`. (The `KitnEssentials.FramePool` reference works because `KE.FramePool = FramePool` was assigned at file-load time, and `KE` is the addon's private namespace alias for `KitnEssentials`.)

Also run:

```
/run local p = KitnEssentials.FramePool:New(function(h) return { row = CreateFrame("Frame", nil, h) } end); p:ReleaseAll(); print("pool ok")
```

**Expected:** prints `pool ok` with no errors. (Constructs a trivial pool, calls `ReleaseAll` on an empty pool — exercises the no-op path.)

If BugSack stays clean, the primitive is loaded and basic semantics work.

- [ ] **Step 6: Commit**

```bash
git add Core/FramePool.lua Core/Core.xml
git commit -m "$(cat <<'EOF'
core: add KE.FramePool reusable frame-pool primitive

New Core/FramePool.lua provides KE.FramePool:New(factory, resetter?)
with Blizzard-style semantics:
- Acquire(parent) borrows a kit, growing the pool on demand. O(1).
- ReleaseAll() marks every active kit idle, reparents them back to a
  hidden holder, optionally runs a resetter. No individual Release.

Kits expose their root Frame as kit.row (or kit.frame) by convention;
sub-frames ride along as descendants. Hidden holder is parented to
UIParent and lives for the session.

No consumers yet — spell browser adoption follows.
EOF
)"
```

---

## Task 2: Refactor spell browser to use pools

**Files:**
- Modify: `GUI/GUIWidgets/GUI-SpellBrowserCard.lua` (in place, ~140 lines changed)

This task is one large logical commit because the factories, configure functions, pool instances, and `CreateSpellBrowserCard` body are all interdependent. Splitting them would stage half-wired code.

- [ ] **Step 1: Replace the entire file**

Overwrite `GUI/GUIWidgets/GUI-SpellBrowserCard.lua` with:

```lua
-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SpellBrowserCard.lua                                ║
-- ║  Purpose: BigWigs spell browser. Search field +          ║
-- ║  per-boss grouped spell list with icons + Use buttons.   ║
-- ║  Used by DungeonTimers per-trigger Cfg page.             ║
-- ║                                                          ║
-- ║  Frames are pooled via KE.FramePool — spell rows, boss   ║
-- ║  headers, and separators reuse instances across renders  ║
-- ║  instead of leaking to UIParent on each ClearContent.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs
local CreateFrame = CreateFrame

---------------------------------------------------------------------------------
-- Factories: build kit shape once, parent to pool's hidden holder
---------------------------------------------------------------------------------

local function CreateSpellRowKit(holder)
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(28)
    row:EnableMouse(true)

    local iconFrame = CreateFrame("Frame", nil, row)
    iconFrame:SetSize(24, 24)
    iconFrame:SetPoint("LEFT", row, "LEFT", 4, 0)

    local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetPoint("TOPLEFT", 1, -1)
    iconTexture:SetPoint("BOTTOMRIGHT", -1, 1)

    local iconBorder = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
    iconBorder:SetAllPoints()
    iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    iconBorder:SetBackdropBorderColor(0, 0, 0, 1)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", iconFrame, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    label:SetJustifyH("LEFT")
    KE:ApplyThemeFont(label, "small")

    local useBtn = GUIFrame:CreateButton(row, "Use", { width = 80, height = 22 })
    useBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    return {
        row = row,
        iconFrame = iconFrame,
        iconTexture = iconTexture,
        iconBorder = iconBorder,
        label = label,
        useBtn = useBtn,
    }
end

local function CreateBossHeaderKit(holder)
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(14)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", row, "LEFT", 4, -4)
    KE:ApplyThemeFont(label, "normal")

    return { row = row, label = label }
end

local function CreateSeparatorKit(holder)
    -- Mirrors GUIFrame:CreateSeparator: a Frame with a 1px texture child.
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(1)

    local tex = row:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.5)

    return { row = row, tex = tex }
end

---------------------------------------------------------------------------------
-- Pool instances: per-kit-type, file scope, live for the session
---------------------------------------------------------------------------------

local spellRowPool   = KE.FramePool:New(CreateSpellRowKit)
local bossHeaderPool = KE.FramePool:New(CreateBossHeaderKit)
local separatorPool  = KE.FramePool:New(CreateSeparatorKit)

---------------------------------------------------------------------------------
-- Configure: per-render data goes here. Uses SetScript (not HookScript) so
-- handlers don't accumulate across reuses.
---------------------------------------------------------------------------------

local function ConfigureSpellRow(kit, spell, onSpellSelect)
    kit.iconTexture:SetTexture(spell.icon or 134400)
    KE:ApplyIconZoom(kit.iconTexture)

    kit.label:SetText(spell.name .. "|cffffffff (" .. spell.spellId .. ")|r")
    kit.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

    local capturedSpellId = spell.spellId
    kit.row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 30, 0)
        GameTooltip:SetSpellByID(capturedSpellId)
        GameTooltip:Show()
    end)
    kit.row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- SetScript (not HookScript) — overwrites prior handlers so stale
    -- closures from previous reuses don't accumulate. The previous
    -- implementation used HookScript, which leaked closures even without
    -- pooling. Fixed in passing.
    kit.useBtn:SetScript("OnClick", function()
        if onSpellSelect then onSpellSelect(capturedSpellId) end
    end)
    kit.useBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_CURSOR_RIGHT", 30, 0)
        GameTooltip:SetSpellByID(capturedSpellId)
        GameTooltip:Show()
    end)
    kit.useBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function ConfigureBossHeader(kit, headerText)
    kit.label:SetText(headerText)
    kit.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
end

local function ConfigureSeparator(kit)
    -- Color is set in factory and doesn't change per-render. Kept as a
    -- function so future style variants (e.g. accent separator) have a
    -- clear extension point.
    kit.tex:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.5)
end

---------------------------------------------------------------------------------
-- Public entry: CreateSpellBrowserCard
---------------------------------------------------------------------------------

function GUIFrame:CreateSpellBrowserCard(scrollChild, yOffset, config)
    config = config or {}
    local title = config.title or "Browse BigWigs Spells"
    local spells = config.spells or {}
    local searchFilter = config.searchFilter or ""
    local onSearchChange = config.onSearchChange
    local onSpellSelect = config.onSpellSelect

    -- Release every pooled kit at the top of every render. Kits reparent
    -- back to their pools' hidden holders; the orphaned old card from
    -- the previous render is left empty and eligible for GC.
    spellRowPool:ReleaseAll()
    bossHeaderPool:ReleaseAll()
    separatorPool:ReleaseAll()

    if #spells == 0 then
        local noBwCard = GUIFrame:CreateCard(scrollChild, "BigWigs Spell Browser", yOffset)
        noBwCard:AddLabel(
            "No BigWigs data available for this dungeon. Make sure BigWigs is installed and the dungeon module is loaded.")
        return noBwCard, noBwCard:GetNextOffset()
    end

    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)

    local searchRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local searchInput = GUIFrame:CreateEditBox(searchRow, "Search spells", {
        value = searchFilter,
        callback = function(text)
            if onSearchChange then onSearchChange(text) end
        end
    })
    searchRow:AddWidget(searchInput, 1)
    card:AddRow(searchRow, Theme.rowHeight)

    local filteredSpells = {}
    local searchLower = searchFilter:lower()
    for _, spell in ipairs(spells) do
        if searchLower == "" or (spell.name and spell.name:lower():find(searchLower, 1, true)) then
            table_insert(filteredSpells, spell)
        end
    end

    local bossGroups = {}
    local bossOrder = {}
    local bossInfo = {}
    for _, spell in ipairs(filteredSpells) do
        local bossKey = spell.sortKey or 999999
        if not bossGroups[bossKey] then
            bossGroups[bossKey] = {}
            table_insert(bossOrder, bossKey)
            bossInfo[bossKey] = {
                name = spell.bossName or "Unknown",
                num = spell.bossNum or 0,
            }
        end
        table_insert(bossGroups[bossKey], spell)
    end

    table.sort(bossOrder)

    for _, bossKey in ipairs(bossOrder) do
        local boss = bossInfo[bossKey]
        local headerText = boss.num > 0
            and string.format("B%d %s", boss.num, boss.name)
            or string.format("— %s —", boss.name)

        local headerKit = bossHeaderPool:Acquire(card.content)
        ConfigureBossHeader(headerKit, headerText)
        card:AddRow(headerKit.row, 14)

        local separatorKit = separatorPool:Acquire(card.content)
        ConfigureSeparator(separatorKit)
        card:AddRow(separatorKit.row, 4)

        for _, spell in ipairs(bossGroups[bossKey]) do
            local rowKit = spellRowPool:Acquire(card.content)
            ConfigureSpellRow(rowKit, spell, onSpellSelect)
            card:AddRow(rowKit.row, 28)
        end
    end

    if #filteredSpells == 0 and searchFilter ~= "" then
        local noMatchRow = GUIFrame:CreateRow(card.content, 30)
        local noMatchLabel = noMatchRow:CreateFontString(nil, "OVERLAY")
        noMatchLabel:SetPoint("LEFT", noMatchRow, "LEFT", 4, 0)
        KE:ApplyThemeFont(noMatchLabel, "small")
        noMatchLabel:SetText("No spells match your search.")
        noMatchLabel:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        card:AddRow(noMatchRow, 30)
    end

    return card, card:GetNextOffset()
end
```

- [ ] **Step 2: Lint clean**

```bash
luacheck GUI/GUIWidgets/GUI-SpellBrowserCard.lua --config .luacheckrc
```

**Expected output:** `Total: 0 warnings / 0 errors in 1 file`

- [ ] **Step 3: wowlua-ls clean (after annotation lands)**

For now, the Problems panel may show `undefined-field 'FramePool' on class 'KE'` because we haven't added the annotation yet. That's expected — it will be fixed in Task 3. Verify the only outstanding warning is that one.

- [ ] **Step 4: Smoke test in WoW**

In-game: `/reload`. Open KE GUI → Dungeons → DungeonTimers → click any dungeon (e.g. Maisara Caverns).

**Expected:**
- Spell browser populates with bosses + spells, identical visual to before.
- Each spell row has icon, name, spellId, and "Use" button.
- Hovering a spell shows its tooltip.
- Hovering the Use button shows the same tooltip.
- Clicking "Use" populates the trigger's spellId field.
- Search filter narrows / widens the list correctly.

**If BugSack reports any error:** stop and diagnose before committing. The most likely failure modes are:
- `attempt to call method 'Acquire' (a nil value)` → FramePool not loaded (check Task 1 step 5).
- Stale tooltip on hover → SetScript ordering issue in `ConfigureSpellRow`.
- Wrong spell ID on Use click → `capturedSpellId` closure bug.

- [ ] **Step 5: Commit**

```bash
git add GUI/GUIWidgets/GUI-SpellBrowserCard.lua
git commit -m "$(cat <<'EOF'
spell-browser: adopt KE.FramePool for rows/headers/separators

Replace per-render CreateFrame chains with three pool instances
(spellRowPool, bossHeaderPool, separatorPool). At top of every
render the pools ReleaseAll(), reparenting kits back to their
hidden holders; the orphaned old card from the previous render
is left empty and eligible for GC.

Captures ~99% of the per-click frame leak. Card itself, search
row, and edit box still recreated per render (small enough to
ignore for now).

Latent bug fixed in passing: previous code used HookScript on
the Use button OnEnter, which accumulates handlers across renders.
Switched to SetScript so handlers overwrite cleanly — required
under pooling, also fixes a pre-existing slow leak in the
non-pooled implementation.

Spec: docs/superpowers/specs/2026-04-29-spell-browser-frame-pool-design.md
EOF
)"
```

---

## Task 3: Annotate `KE.FramePool` for wowlua-ls

**Files:**
- Modify: `Annotations/KE.lua` (gitignored — local dev artifact only)

- [ ] **Step 1: Add the FramePool class declaration**

Open `Annotations/KE.lua`. Find the `KE = {}` block (around line 50, where `---@class KE` is declared). Find the line:

```lua
---@field defaults table
local KE = {}
```

Insert ABOVE that line (so the new class is defined before `KE` references it):

```lua
---@class KE.FramePool
local KE_FramePool = {}

--- Create a new typed pool.
---@param factory  fun(holder: Frame): table
---@param resetter fun(kit: table)?
---@return KE.FramePool
function KE_FramePool:New(factory, resetter) end

--- Borrow a kit, reparenting it to `parent`. Grows the pool on demand.
---@param parent Frame
---@return table kit
function KE_FramePool:Acquire(parent) end

--- Mark every active kit as idle. Reparents kits back to the pool's
--- hidden holder. Always called at the top of a render.
function KE_FramePool:ReleaseAll() end

```

Then find the `@field` block on `KE`:

```lua
---@class KE
---@field db AceDB
---@field FONT string
---@field LSM table
---@field Theme KETheme
---@field GUIFrame table
---@field EditMode table
---@field ProfileManager table
---@field DungeonTimerPresets table
---@field GUI table
---@field defaults table
local KE = {}
```

Add an entry for `FramePool`:

```lua
---@class KE
---@field db AceDB
---@field FONT string
---@field LSM table
---@field Theme KETheme
---@field GUIFrame table
---@field EditMode table
---@field ProfileManager table
---@field DungeonTimerPresets table
---@field GUI table
---@field FramePool KE.FramePool
---@field defaults table
local KE = {}
```

- [ ] **Step 2: Reload wowlua-ls**

`Ctrl+Shift+P` → "Developer: Reload Window" in VS Code.

- [ ] **Step 3: Verify Problems panel is clean**

Open both `Core/FramePool.lua` and `GUI/GUIWidgets/GUI-SpellBrowserCard.lua`. Check Problems panel for either file.

**Expected:** 0 issues on both. Specifically the previous `undefined-field 'FramePool' on class 'KE'` warning at the spell browser file should now be gone.

- [ ] **Step 4: No commit**

`Annotations/KE.lua` is gitignored. This task is a local-only annotation update; nothing to commit. Skip to Task 4.

---

## Task 4: Verification

**Files:** None modified. This task runs the verification protocol from the spec and documents the result.

- [ ] **Step 1: Cold baseline measurement**

In-game in town: `/reload`.

Wait 5 seconds for KE to initialize fully.

Run:

```
/run UpdateAddOnMemoryUsage(); print(string.format("KE cold: %.2f MB", GetAddOnMemoryUsage("KitnEssentials")/1024))
```

**Expected:** something in the range `KE cold: 12.00 MB` to `KE cold: 18.00 MB`. Record the actual value as **`baseline`**.

- [ ] **Step 2: First-pass through all 8 dungeons**

Open KE GUI → Dungeons → DungeonTimers panel.

Click each of the 8 dungeons in sequence, waiting ~1 second between clicks for the spell browser to populate from BigWigs:

1. Magisters' Terrace
2. Maisara Caverns
3. Nexus-Point Xenas
4. Windrunner Spire
5. Algeth'ar Academy
6. Pit of Saron
7. Seat of the Triumvirate
8. Skyreach

After the 8th click, run:

```
/run UpdateAddOnMemoryUsage(); print(string.format("KE first-pass: %.2f MB", GetAddOnMemoryUsage("KitnEssentials")/1024))
```

Record this value as **`first_pass_peak`**.

- [ ] **Step 3: Second-pass through all 8 dungeons**

Click through the same 8 dungeons in the same order, same cadence. After the 8th click:

```
/run UpdateAddOnMemoryUsage(); print(string.format("KE second-pass: %.2f MB", GetAddOnMemoryUsage("KitnEssentials")/1024))
```

Record as **`second_pass_peak`**.

- [ ] **Step 4: Apply pass/fail criterion**

Compute `delta = second_pass_peak - first_pass_peak`.

| Result | Outcome |
|---|---|
| `delta <= 1.5 MB` | **PASS** — pool is bounding memory growth as expected. Proceed to Step 5. |
| `delta > 1.5 MB` | **FAIL** — leak still firing. Do NOT mark this task complete. Investigate: (a) confirm `pool:ReleaseAll()` is called in CreateSpellBrowserCard, (b) confirm pool instances are file-scope and not function-local, (c) check BugSack for silent errors during render. |

- [ ] **Step 5: Visual regression checks**

Without `/reload`, exercise the spell browser:

- [ ] Re-click a dungeon you already viewed. Spell list populates identically (same icons, names, IDs).
- [ ] Hover several spell rows. Tooltip shows the *current* spell's info, not stale data from a prior render. (This validates the SetScript-vs-HookScript fix.)
- [ ] Click a "Use" button on a spell. Verify the trigger's spellId field updates to that spell's ID.
- [ ] Type into the search box. Watch rows appear/disappear cleanly. No orphan rows visible on top of the filtered list.
- [ ] Clear the search. Full list returns. No visual glitches.

**If any visual regression appears:** stop and diagnose before continuing.

- [ ] **Step 6: BugSack sanity**

Check BugSack. **Expected:** no errors fired during the entire verification protocol.

- [ ] **Step 7: Document results in the spec**

Append a verification results section to the spec doc. Edit `docs/superpowers/specs/2026-04-29-spell-browser-frame-pool-design.md` and add at the bottom:

```markdown
## Verification results — YYYY-MM-DD

| Measurement | Value |
|---|---|
| KE cold baseline | X.XX MB |
| First-pass peak (after 8 dungeons) | X.XX MB |
| Second-pass peak (after 8 more) | X.XX MB |
| Delta (second − first) | X.XX MB |
| Pass criterion (≤ 1.5 MB) | PASS / FAIL |

Visual checks:
- [x] Repeat-click shows identical list
- [x] Tooltip shows current spell (no stale data)
- [x] Use button populates correct spellId
- [x] Search filter transitions cleanly
- [x] BugSack clean throughout
```

Replace `YYYY-MM-DD` with today's date and `X.XX` with actual measured values.

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/specs/2026-04-29-spell-browser-frame-pool-design.md
git commit -m "$(cat <<'EOF'
docs: spell-browser frame-pool verification results

Recorded measurement results from the verification protocol after
the pool refactor landed. Pass criterion met (delta <= 1.5 MB).
Visual regression checks all clean.
EOF
)"
```

---

## Self-review checks (run before declaring plan complete)

**1. Spec coverage** — every requirement in `2026-04-29-spell-browser-frame-pool-design.md` maps to a task:

| Spec section | Task |
|---|---|
| Component 1 (FramePool primitive) | Task 1 |
| Component 2 (spell browser adoption) | Task 2 |
| Component 3 (lifecycle integration) | Task 2 (no separate work — handled by ReleaseAll-at-top-of-render) |
| Component 4 (verification protocol) | Task 4 |
| Files-touched: `Core/FramePool.lua` | Task 1 |
| Files-touched: `Core/Core.xml` | Task 1 |
| Files-touched: `GUI-SpellBrowserCard.lua` | Task 2 |
| Files-touched: `Annotations/KE.lua` | Task 3 |
| HookScript→SetScript bug fix | Task 2 step 1 (in `ConfigureSpellRow`) |

**2. Placeholder scan** — no "TODO", "TBD", "implement later", or vague "add appropriate handling" anywhere in this plan. Every code block contains the actual implementation.

**3. Type consistency**:
- `KE.FramePool:New(factory, resetter)` — same signature in Task 1 (definition), Task 2 (3 call sites), Task 3 (annotation).
- `Acquire(parent)` returns `kit` (a table) — consistent across pool primitive and all 3 configure functions.
- `kit.row` convention used by primitive's `SetParent` logic — every factory in Task 2 returns a table containing `row` as the root Frame.
- `KE:ApplyIconZoom`, `KE:ApplyThemeFont` — used in factories + configure, names match existing helpers in `Core/Widgets.lua`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-29-spell-browser-frame-pool.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks. Best for keeping main-conversation context lean.

2. **Inline Execution** — Execute tasks in this session using `executing-plans`, batch with checkpoints between tasks.

Which approach?

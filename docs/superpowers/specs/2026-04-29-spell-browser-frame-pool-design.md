# Spell Browser Frame Pool — Design

**Date:** 2026-04-29
**Status:** Design approved, awaiting implementation plan
**Scope owner:** Single-session refactor (~2 hours)

## Context

When the user clicks through DungeonTimers' per-dungeon tabs in the GUI,
KE's memory line (visible in the addon-usage tooltip) climbs monotonically
— roughly +1 MB per click for the first ~10 clicks, asymptoting around
30 MB and continuing to creep upward over a session. The cause is the
spell-browser card recreating ~6 frames per spell × ~50 spells per
dungeon = ~300 frames per click, with no reuse. `ContentArea.ClearContent()`
hides each old child and reparents to nil, which orphans frames to
UIParent rather than destroying them — WoW has no `DestroyFrame` API.

This leak was identified in `project_dungeontimers_memory_leak.md` and
deferred while higher-priority GC churn fixes shipped earlier in the
same session (the `OnVisualUpdate` text-gating + `FormatText` rewrite,
commit `765f2d0`). Those fixes addressed the user-perceivable performance
issue (35 MB GC churn cycles → 10 MB cycles). This refactor closes the
remaining frame-pool leak.

**User-facing effect of this refactor:**
- KE memory plateaus at ~22–25 MB instead of climbing past 30 MB.
- Click responsiveness: borderline imperceptible improvement.
- GC hitches: marginally less frequent during long GUI sessions.
- A reusable `KE.FramePool` primitive becomes available for future
  adopters (timer-list buttons, position cards, other "rebuilt every
  render" widgets).

## Decisions made during brainstorming

| Question | Choice | Rationale |
|---|---|---|
| Pool scope | **C — Extract reusable `KE.FramePool` primitive** | Apply to spell rows + boss headers + separators today; pattern available for future adopters. ~99% leak coverage. |
| API shape | **A — Blizzard-style `ReleaseAll()` + `Acquire(parent)`** | Matches `FramePool` / `FramePoolMixin` semantics every WoW UI dev knows. Render model is "release → reacquire per render." |
| Multi-kit handling | **A — Per-kit-type pools, multiple instances per adopter** | Type-pure pools, no internal dispatch. Spell browser instantiates 3 (spellRow, bossHeader, separator). |

## Component 1 — `KE.FramePool` primitive

**Location:** `Core/FramePool.lua`. New file. Loaded via `Core/Core.xml`
early (before GUI widgets, since GUI depends on Core).

**Public API:**

```lua
---@class KE.FramePool
KE.FramePool = {}

--- Create a new typed pool.
---@param factory  fun(holder: Frame): table   -- creates one kit, parent = pool's hidden holder
---@param resetter fun(kit: table)?            -- optional; clears scripts/state on release
---@return KE.FramePool
function KE.FramePool:New(factory, resetter) end

--- Borrow a kit, reparenting to `parent`. Grows the pool on demand.
---@param parent Frame
---@return table kit
function KE.FramePool:Acquire(parent) end

--- Mark every active kit as idle. Reparents kits back to the pool's
--- hidden holder and calls `resetter` on each. Always called at the
--- top of a render before any Acquire.
function KE.FramePool:ReleaseAll() end
```

**Internal state:**

- `_holder` — single hidden `Frame` parented to `UIParent`. Owns idle kits.
- `_kits` — array of every kit ever created.
- `_activeCount` — `_kits[1..activeCount]` are checked out; the rest are idle.

**Acquire algorithm (O(1) amortized):**
1. `_activeCount += 1`
2. If `_kits[_activeCount]` exists → reparent to `parent`, show, return.
3. Else → call `factory(_holder)`, append to `_kits`, reparent to `parent`,
   show, return.

**ReleaseAll algorithm:**
1. For `i = 1, _activeCount`: reparent `_kits[i]` to `_holder`, hide,
   call `resetter(kit)` if set.
2. `_activeCount = 0`.

**Design properties:**
- Pool size is monotonic (never shrinks). Acceptable — peak is bounded
  by the largest dungeon's spell count.
- Idle kits stay alive (parented to `_holder`), never visible to
  `ClearContent`.
- No weak refs, no cleanup hooks. Pool objects are file-locals in
  adopters; they live for the session.
- No individual `Release(kit)` API. Only `ReleaseAll`. KE's render model
  is "rebuild between renders" — partial release is YAGNI.

## Component 2 — Spell browser adoption

**Location:** Refactor in place at
`GUI/GUIWidgets/GUI-SpellBrowserCard.lua`. No new files.

**Three pool instances at file scope:**

```lua
local spellRowPool   = KE.FramePool:New(CreateSpellRowKit)
local bossHeaderPool = KE.FramePool:New(CreateBossHeaderKit)
local separatorPool  = KE.FramePool:New(CreateSeparatorKit)
```

No `resetter` is passed for any of the three pools. Each kit's per-render
state (icon, text, scripts) is fully replaced by its `Configure*` function
on every `Acquire`, so there is nothing to clear on `Release`. Future
adopters with conditional fields may need one.

**Three factory functions** (also file scope, before pool declarations).
Each takes the pool's hidden holder as parent and builds the kit's frame
structure once. Example for spell row:

```lua
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

    return { row = row, iconFrame = iconFrame, iconTexture = iconTexture,
             iconBorder = iconBorder, label = label, useBtn = useBtn }
end
```

**One configure function per kit type.** Per-render data — icon, text,
captures, scripts. Critical: must use `SetScript` not `HookScript` for
all event handlers, otherwise stale closures accumulate across reuses.

```lua
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
    -- closures from previous reuses don't accumulate.
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
```

**Latent bug fixed in passing:** the existing code uses
`useBtn:HookScript("OnEnter", ...)` which *accumulates* handlers. Even
without pooling, that means each render adds a new closure to the button.
Switching to `SetScript` is mandatory under pooling and fixes a pre-
existing slow leak.

**`CreateSpellBrowserCard` body becomes:**

```lua
function GUIFrame:CreateSpellBrowserCard(scrollChild, yOffset, config)
    spellRowPool:ReleaseAll()
    bossHeaderPool:ReleaseAll()
    separatorPool:ReleaseAll()

    -- ... rest of function unchanged, except every CreateFrame for these
    -- kit types is replaced with `pool:Acquire(card.content)` followed by
    -- `Configure*(kit, ...)` and `card:AddRow(kit.row, height)`.
end
```

**Not pooled (stays as today):**
- The card itself (1 frame per render).
- The search row + edit box (1 each per render).
- The "no BigWigs data" / "no match" empty-state cards (rare, transient).

Future passes could pool these too. YAGNI for this scope.

## Component 3 — Lifecycle integration

**The problem:** `ContentArea.ClearContent()` at
`GUI/GUIMain/GUI-ContentAreas.lua:89-101` does
`child:Hide(); child:SetParent(nil)` on every direct child of
`scrollChild`. The pool must coexist without losing kits.

**Render lifecycle, before vs. after:**

| Step | Today | After pooling |
|---|---|---|
| 1. User clicks dungeon B | `RefreshContent()` runs | Same |
| 2. ClearContent fires | Orphans card A (and descendants — including spell rows) to nil-parent | Same |
| 3. Panel-builder runs | `CreateSpellBrowserCard()` called | Same |
| 4. Top of CreateSpellBrowserCard | Builds card B + 50 fresh CreateFrame calls | Calls `pool:ReleaseAll()` on all 3 pools — kits reparent back to their pool's hidden holder |
| 5. Render loop | 50 × CreateFrame + configure | 50 × `pool:Acquire(card.content)` + `Configure()` |
| 6. End of render | Card B with 50 fresh kit children | Card B with 50 borrowed kit children |

**Key invariant:** kits ride along with the orphaned card briefly (between
ClearContent and the next ReleaseAll), but the pool holds strong
references in its `_kits` array. Reparenting via
`kit.row:SetParent(pool._holder)` works regardless of current parent
state. The window is microseconds — both run inside the same synchronous
`RefreshContent()` pass.

**No changes needed to ContentArea.** Pool lifecycle is local to the
adopter file. Decision-rejected alternative: registering pools with
ContentArea so ClearContent could call `ReleaseAll` first. Rejected
because it centralizes a local concern and adds an undesired dependency
direction (Core/widgets → Core/ContentAreas).

**No changes needed to `contentCleanupCallbacks` registry.** That fires
on tab teardown; pool lifecycle is per-render.

**Edge cases handled:**

- *GUI close/reopen:* ContentArea isn't torn down on close (existing
  behavior reuses it on next open). Pool kits stay alive in their
  holders. No leak from open/close cycles.
- *Search filter narrows:* user types "fear", 50 spells become 3.
  Render acquires 3; the other 47 stay idle in pool. Clearing the search
  re-acquires up to 50, reusing existing kits where possible.
- *Separator is a Texture, not a Frame:* `GUIFrame:CreateSeparator`
  returns a Frame containing a Texture, so the kit-as-Frame model holds.

## Component 4 — Verification

**Primary success metric:** KE's row in the addon-usage tooltip
plateaus at a steady-state value when clicking through all 8 dungeons
twice in sequence.

**Reproduction script (manual, ~3 minutes):**

1. `/reload` in town. Note KE memory baseline:
   `/run UpdateAddOnMemoryUsage(); print(GetAddOnMemoryUsage("KitnEssentials"))`.
   Expected: ~12–15 MB cold.
2. Open KE GUI → Dungeons → DungeonTimers panel.
3. Click each of the 8 dungeons in sequence, ~1 sec apart.
4. After 8th click, query KE memory. **First-pass peak.**
   Expected: ~22–28 MB.
5. Click through all 8 dungeons again, same cadence.
6. Query KE memory. **Second-pass peak.**

**Pass criterion:** `second_pass_peak - first_pass_peak <= 1.5 MB`.
Some variance from incidental allocations (font cache, tooltip strings)
is acceptable; 1.5 MB is the conservative tolerance.

**Fail criterion:** `second_pass_peak - first_pass_peak > 1.5 MB`. The
leak is still firing — investigate before declaring done. Single
threshold so the result is unambiguously pass or fail.

**Secondary verification — visual:**

- Re-clicking a dungeon shows identical spell list (regression check on
  configure step).
- Hovering a spell row shows the *current* spell's tooltip (validates
  `SetScript` overwrite vs. accumulating `HookScript`).
- Use button populates the trigger with the correct spell ID.
- Search filter narrowing/widening shows clean transitions, no orphan
  rows visible on top of new filtered list.

**Tertiary verification — runtime sanity:**

- `luacheck Core/FramePool.lua GUI/GUIWidgets/GUI-SpellBrowserCard.lua --config .luacheckrc` → 0 new warnings.
- wowlua-ls Problems panel for both files → 0 issues.
- BugSack stays clean during the reproduction script.
- `/api-validate` not required (no combat data, no Secret Values).

**Not measuring:**

- Click latency (sub-perceptual delta, already addressed by earlier
  session work).
- GC sweep frequency (visible only to memory profilers).
- Other dungeon timer modules (out of scope).

## Out of scope

- Pooling the search row, search input, or card itself.
- Pooling for other GUI cards (timer list buttons, position cards).
  Pattern is now available; adoption is per-future-session.
- Modifying `ContentArea.ClearContent()`. Rejected; lifecycle is local.
- Individual `pool:Release(kit)` API. Render model doesn't need it.
- `pool:GetKits()` or other introspection helpers. YAGNI.

## Risks and unknowns

- **`SetParent` on a Texture.** Separators are Frames containing
  Textures (per `GUIFrame:CreateSeparator`), so the kit-as-Frame model
  works. If we discover a separator implementation that returns a raw
  Texture, the separator factory would need to wrap it in a Frame
  explicitly. Mitigated by reading the existing helper before write.
- **First render after `/reload`.** Pool is empty; `Acquire` calls go
  through `factory` for all 50 spells. Same cost as today's first
  render. No regression, no improvement.
- **BigWigs version drift.** If BigWigs adds spells, per-dungeon kit
  count varies. Pool plateau shifts but stays bounded. Re-baseline
  verification numbers if BigWigs version changes.
- **wowlua-ls type warnings on `KE.FramePool`.** Need to add
  `KE.FramePool` to `Annotations/KE.lua` after the implementation
  lands so call sites don't show as undefined.

## Files touched

| File | Action |
|---|---|
| `Core/FramePool.lua` | Create |
| `Core/Core.xml` | Add `<Script file="FramePool.lua"/>` line |
| `GUI/GUIWidgets/GUI-SpellBrowserCard.lua` | Refactor in place |
| `Annotations/KE.lua` | Add `KE.FramePool` class declaration (post-implementation) |

## Verification of design completeness

- [x] All 4 design sections explicitly approved by user.
- [x] Three brainstorm decisions captured with rationale.
- [x] Files-to-touch list is complete.
- [x] Pass/fail criteria are objective and measurable.
- [x] Out-of-scope list is explicit (no scope creep into B/C alternatives
      from earlier discussion).
- [x] Risks are real and have mitigations.

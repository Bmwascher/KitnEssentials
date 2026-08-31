# KitnEssentials headless tests

Static analysis + headless unit/smoke tests that run **outside** the game, as a
fast layer *under* in-game `/reload` testing. They do **not** replace it —
anything visual, secure-frame, taint, EditMode, or true event-sequence behaviour
is still verified in-game.

All of this tooling is **git-tracked but stripped from the player zip** via
`.pkgmeta` `ignore:`. Players never receive `dev/`, `.busted`, `.luacheckrc`,
or `.github/`.

## What runs

| Layer | Tool | Catches |
|-------|------|---------|
| Static analysis | `luacheck` | typo'd/undefined globals, unused vars, shadowing (12.0 API contract lives in `.luacheckrc`) |
| Compile smoke | `busted` → `dev/spec/smoke_spec.lua` | syntax errors in any shipped `Core/`, `Modules/`, `GUI/` file (one check per file) |
| Unit specs | `busted` → `dev/spec/*_spec.lua` | logic in pure + API-adjacent code |

### The honesty boundary (read this before trusting a mock)

`dev/spec/_wow_mock.lua` stubs only what a test touches. A mock verifies *"does my
code branch correctly given a value I **declare** secret/restricted"* — **not**
*"is my understanding of 12.0 secret/taint semantics correct."* True
secret/taint runtime behaviour is in-game-only. Tests that lean on declared
secret values say so in comments; keep that distinction when adding specs.

### Testability tiers

- **Tier 1 — pure data/logic** (e.g. `Core/Interrupts.lua`): load and assert directly, no mock.
- **Tier 2 — logic around the WoW API** (e.g. `Core/Secret.lua`): drive via `dev/spec/_wow_mock.lua`; deterministically fire events through recorded frame handlers.
- **Tier 3 — frame layout / visual / EditMode / GUI**: in-game only. Out of scope here.

## Running

From the repo root:

```sh
busted            # unit specs + compile smoke
luacheck .        # static analysis (strict — zero-warning baseline since 2026-06-11)
```

## One-time local setup

### Windows (hererocks — Lua 5.1.5, matching WoW and CI)

The suite runs under Lua **5.1.5** everywhere (WoW's embedded major version):
a dedicated hererocks tree holds the interpreter plus busted/luacov, wired up
by the scoop LuaRocks. Needs python and a C compiler (mingw gcc) on PATH.

```powershell
scoop install luarocks
python -m pip install hererocks
python -m hererocks "$HOME\Documents\WoW-Dev\lua51" -l 5.1.5
luarocks --lua-version=5.1 --lua-dir="$HOME\Documents\WoW-Dev\lua51" --tree="$HOME\Documents\WoW-Dev\lua51" install busted 2.3.0-1
luarocks --lua-version=5.1 --lua-dir="$HOME\Documents\WoW-Dev\lua51" --tree="$HOME\Documents\WoW-Dev\lua51" install luacov 0.17.0-1
luarocks --lua-version=5.1 --lua-dir="$HOME\Documents\WoW-Dev\lua51" --tree="$HOME\Documents\WoW-Dev\lua51" install luacheck
```

luacheck must be the LuaRocks rock (runs through the tree's `lua.exe`), NOT
the standalone `luacheck.exe` from scoop/GitHub releases: that binary is
unsigned and Windows 11 **Smart App Control** blocks it outright
(CodeIntegrity events 3033/3077; SAC has no per-file exclusions). Confirmed
2026-07-03 — the old standalone exe is parked at
`%LOCALAPPDATA%\Programs\luacheck\luacheck.exe.sac-blocked`.

(Skip hererocks' own LuaRocks (`-r`) — its Windows installer is broken; the
scoop LuaRocks manages the tree fine via `--lua-version/--lua-dir/--tree`.)

Prepend the tree's `bin` to your **user PATH** so `lua`, `busted`, and
`luacov` (and the pre-push hook) resolve from it:

```powershell
[Environment]::SetEnvironmentVariable(
  "Path", "$HOME\Documents\WoW-Dev\lua51\bin;" + [Environment]::GetEnvironmentVariable("Path","User"), "User")
```

### Linux / WSL / the cloud

```sh
bash dev/scripts/setup-lua-toolchain.sh
```

CI no longer uses this; it remains for Claude Code cloud environments — point
the **Claude Code on the web** environment setup script at it so cloud
sessions have `luacheck` + `busted` and the recurring "no Lua interpreter / no
busted on this box" message stops.

## Pre-push gate (optional)

```sh
git config core.hooksPath dev/githooks
```

Runs the comment and commit-message guards over the pushed range, then
`luacheck` + `busted`, all blocking, before every push — each tool
gates independently, so a machine missing one still runs the other. Also
prints a non-blocking note when `.luacheckrc` drifts from the local WoW API
reference (see `dev/scripts/check-luacheckrc-drift.lua`). Override a single
push with `git push --no-verify`. If a tool isn't on PATH the hook skips it
with a notice rather than blocking (CI still runs everything).

The `commit-msg` and `pre-commit` guards match against a word list kept in
`dev/githooks/upstream-names.local.sh`, which is gitignored: this repo is
public, and publishing the list leaks the provenance the guards exist to keep
out of history and shipped comments. Restore it from the local backup after a
re-clone, alongside `.claude/` and `AGENTS.md`. Both guards block outright
when the file is absent rather than waving everything through. Format:

```sh
stems='a|b|c'      # reference sources, matched anywhere in a token
shorts='x|y'       # their short forms, matched at word boundaries only
compat='d|e'       # addons the project legitimately names, see below
provenance='...'   # the vocabulary, dates included, that makes a compat name a leak
namesCI='F|G'      # people/agents, word-bounded, case-insensitive
namesCS='H|I'      # people/agents that double as plausible WoW words, capitalised only
```

`stems` and `shorts` block on sight. `compat` holds addons KE detects, skins,
or stands modules down under, so their names belong in ordinary entries and
comments; those block only where `provenance` matches the same message or
comment line — "stand down when ElvUI handles skinning" passes, "port the
ElvUI skin path" does not. Moving a name between the two sets is a one-line
edit, and beats living on `--no-verify`.

`commit-msg` uses `stems`, `shorts`, `compat`, and `provenance`; `pre-commit`
uses all of those except `shorts`, plus `namesCI` and `namesCS`. A guard blocks
when any set it needs is missing or empty.

`pre-push` then re-runs both scans, blocking, over everything the push would
publish, one commit at a time: each commit's own added comments and its own
message. The commit-time hooks are skippable with `--no-verify` and other
tools commit without them at all, so this is the last gate before anything
reaches the remote. Per commit rather than end to end, because a comment
added in one commit and removed in a later one never shows up in a range diff
yet still publishes. Tag pushes are scanned too, since a tag carries commits
of its own.

The commit set is whatever the destination remote does not have: bounded by
the sha git advertises when this clone holds that object, and otherwise by
that remote's own tracking refs. A push straight to a URL matches no tracking
refs at all and so reads the whole history. Any git failure blocks the push
instead of reading as a clean scan. Merges are diffed against their first
parent, so a comment invented while resolving a conflict is caught. Block
comments are followed through their body lines, which carry no delimiter of
their own, in Lua at any bracket level and in XML. All three hooks share one
matcher, `dev/githooks/lib/name-guards.sh`, and refuse to run without it or
without a valid word list.

Two gaps are known and left open, both narrow, both cheaper to accept than to
close. Tracking refs are local: if a remote branch is deleted or rewritten
and the stale ref is never pruned, a new ref pointing into it is subtracted
from the scan. Scanning with no exclusions at all would close that, at the
cost of reading the entire history on every first push of a branch. And a
line added INSIDE a block comment whose opener the hunk does not contain
reads as ordinary code, because a diff carries no state from above the hunk;
closing that means scanning the postimage of each changed file instead of the
diff.

`Libs/` is out of scope: the comment rules govern what this project writes,
not the third-party code it embeds, and upstream library headers carry dates
and version stamps by right.

Date forms the comment ban catches: `2026-08-04`; a month name in any case,
separated from its year by any run of spaces, tabs or a comma; and `08/31/26`
or `31/08/26` along with their four-digit year forms. Slash dates need one
component that can be a month and another that can be a day, so spell range
and rank lists such as `30/33/36` stay clean.

## Updating the API reference

```sh
lua dev/scripts/update-api-reference.lua
```

One command: fast-forwards the `.wow-api-reference` clone (and the
BlizzardInterfaceResources clone) to the live build, then reports every API
change since the last update that intersects KE's used surface — removed or
changed functions/events/enums you use, C-side global/CVar changes, and
notable additions. Exit 1 means something you use changed — read the
report before coding. `--report-only` re-prints without fetching;
`--seed` re-baselines. Snapshots live in `WoW-Dev\api-drift-snapshots\`.

## Claude Code hooks (restore after a re-clone or PC reset)

Everything under `.claude/` is gitignored, so the edit-time lint hook and the
main-branch guard die with the checkout. The tracked templates in
`dev/claude-hooks/` are the durable copies — restore them (and the pre-push
`core.hooksPath` config) with:

```powershell
pwsh dev/scripts/install-claude-hooks.ps1
```

Agent config more broadly — `.claude/`, `.agents/`, `AGENTS.md`, `CLAUDE.md`,
and `dev/docs/` — is deliberately local-only; none of it lives in git. After
a re-clone, restore it from the local backup/export, not from this repo.

Idempotent; merges missing hook entries per event (keyed on the hook script
filename) and never overwrites existing entries or personal permissions in
`.claude/settings.json`. When changing a live hook under `.claude/hooks/`,
mirror the change into `dev/claude-hooks/` so the template stays current.

Repo-scope hooks: `branch-guard.ps1` (PreToolUse, blocks .lua/.xml edits on
main) and `luacheck-postedit.ps1` (PostToolUse, lints every .lua edit).

## Multi-model verification (crosscheck plugin)

The multi-model-verify skill (Fable 5 / GPT-5.6 Sol debate gates at plan
time and diff time), the superpowers review-companion hook, the swappable
implementer agent, and their eval harness live in the private **crosscheck**
plugin — repo `Bmwascher/crosscheck`, local working copy at
`Documents/crosscheck`. It installs user-scope through Claude Code's plugin
system (`claude plugin install crosscheck@crosscheck`), so it works in
every project with zero per-repo wiring. Evals and CI for the skill run in
that repo, not here.

## Adding a spec

Simple files load directly via `helpers.loadModule`; the big modules
(DungeonTimers, Core/Globals, DamageMeter core, PixelPerfect, Nicknames)
have ready-made stub sets in `dev/spec/_ke_loader.lua` — use those instead
of hand-rolling stubs.

```lua
local helpers = require("dev.spec._helpers")
local mock    = require("dev.spec._wow_mock")   -- only if the file touches WoW API
local L       = require("dev.spec._ke_loader")  -- per-module loaders (stubs + real load)

describe("MyThing (Modules/.../MyThing.lua)", function()
    it("does the thing", function()
        mock.install()                       -- Tier 2 only
        local KE = helpers.loadModule("Modules/Foo/MyThing.lua", { Print = function() end })
        assert.equals(expected, KE:SomePureFunction(input))
    end)
end)

describe("Globals helpers", function()
    it("resolves sparse colors", function()
        local KE = L.loadGlobals()           -- stub set + real Core/Globals.lua
        assert.same({ 1, 0, 0.549, 1 }, { KE:ResolveColor(nil, { 1, 0, 0.549, 1 }) })
    end)
end)
```

Install mocks and stubs unconditionally in `setup`/`before_each` (no `or`
guards latching stale globals), and give any spec that branches on
declared-secret values the honesty-boundary comment (see above).

Local and CI both run busted under Lua **5.1.5** — the same major version as
WoW's embedded runtime — and `luacheck` enforces 5.1 semantics statically on
top. Keep all spec/harness code 5.1-compatible.

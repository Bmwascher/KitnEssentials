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

### Windows (scoop)

```powershell
scoop install lua luarocks luacheck
luarocks install busted --lua-dir="$(scoop prefix lua)"
```

`luarocks` installs `busted` to `%APPDATA%\luarocks\bin`. Add that dir to your
**PATH** so `busted` (and the pre-push hook) resolve it:

```powershell
[Environment]::SetEnvironmentVariable(
  "Path", "$env:APPDATA\luarocks\bin;" + [Environment]::GetEnvironmentVariable("Path","User"), "User")
```

(busted needs a C compiler for two dependencies — TDM-GCC / mingw on PATH.)

### Linux / WSL / the cloud

```sh
bash dev/scripts/setup-lua-toolchain.sh
```

This same script is what GitHub Actions runs, and what the **Claude Code on the
web** environment setup script should point at — once it does, cloud sessions
have `luacheck` + `busted` and the recurring "no Lua interpreter / no busted on
this box" message stops.

## Pre-push gate (optional)

```sh
git config core.hooksPath dev/githooks
```

Runs `luacheck` + `busted`, both blocking, before every push. Override a
single push with `git push --no-verify`. If a tool isn't on PATH the hook
skips it with a notice rather than blocking (CI still runs everything).

## Adding a spec

```lua
local helpers = require("dev.spec._helpers")
local mock    = require("dev.spec._wow_mock")   -- only if the file touches WoW API

describe("MyThing (Modules/.../MyThing.lua)", function()
    it("does the thing", function()
        mock.install()                       -- Tier 2 only
        local KE = helpers.loadModule("Modules/Foo/MyThing.lua", { Print = function() end })
        assert.equals(expected, KE:SomePureFunction(input))
    end)
end)
```

CI runs busted under Lua 5.4; `luacheck` enforces Lua 5.1 semantics (WoW's
runtime) statically, so keep helpers 5.1-compatible.

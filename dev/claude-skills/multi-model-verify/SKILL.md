---
name: multi-model-verify
description: Use when planning a reference-addon port or WoW 12.0 API-sensitive module work that needs cross-model verification before implementation, or when an implemented diff must be checked against its plan and reference addon before merge. Fires automatically alongside superpowers requesting-code-review via the review-companion hook.
---

# Multi-Model Verify

## Overview

Two equal-weight advisors — Fable 5 (this session) and GPT-5.6 Sol (via the
codex CLI) — verify and refute each other's claims before the cheap
implementer touches code. Sol's documented fabrication risk (METR) is
mitigated by the debate structure — evidence grounding plus mutual
refutation — not by down-weighting either side.

**REQUIRED READING before the first round:** references/debate-protocol.md.

Companion to superpowers, not a replacement: it fills the cross-model review
gap superpowers rules out of scope. `/codex:adversarial-review` remains the
human-invoked pre-merge gate; if the codex plugin's stop-review-gate is
toggled on, its stop-time review overlaps mode `diff` — expected, not a bug.

## When to use

- **Mode `plan`** — after superpowers brainstorming proposes approaches for a
  port or API-sensitive module, before the implementation plan is written.
- **Mode `diff`** — after implementation, alongside superpowers
  requesting-code-review (the review-companion hook injects this
  automatically with the matching base/head SHAs).
- NOT for plain bugfixes, docs or release chores, GUI tweaks, or lint sweeps.

## Preflight (both modes)

1. `codex --version` must succeed — on failure follow references/fallbacks.md
   (degraded mode, visibly flagged; never silently skip cross-vendor review).
2. The reference folder must exist under `References/` (quote paths — several
   contain spaces, e.g. `References/M+ Timer`). Missing → ask the user for
   the path. Never debate reference behavior from memory. If the folder
   holds version subdirectories (e.g. a `v1.4/` next to a `v1.1_old/`), use
   the newest unless the user names one, and cite the versioned path:
   `References/<addon>/<version>/<file>:<line>`.

## Mode plan

1. Draft the Fable position: chosen approach, port-fidelity claims, WoW 12.0
   API risk register. Every reference claim cites a
   `References/<addon>/<file>:<line>` actually read this session; every API
   claim cites `.wow-api-reference/` or an in-game probe result. The
   position has no separate artifact — it IS the claims section of the
   step-2 brief.
2. Compose Sol's debate brief per references/model-prompting-notes.md, write
   it to a scratchpad file, then run round 1:

   ```powershell
   Get-Content -Raw <brief-file> | codex exec --sandbox read-only -m gpt-5.6-sol -c model_reasoning_effort=high --output-last-message <reply-file> -
   ```

   Capture the `session id:` line printed in the run header (top of output);
   read Sol's reply from `<reply-file>` — the stdout transcript logs every
   file Sol reads and can run tens of KB, with the reply buried at the
   bottom.
3. Later rounds keep Sol's state by resuming that session — flags MUST
   precede the resume subcommand (flags after it are a usage error):

   ```powershell
   codex exec --sandbox read-only -m gpt-5.6-sol -c model_reasoning_effort=high --output-last-message <reply-file> resume <SESSION_ID> "<rebuttal-brief>"
   ```

4. Iterate per debate-protocol.md until convergence or the round cap, then
   escalate any unresolved points to the user with both positions stated.
5. Freeze the converged plan per references/frozen-plan-format.md under the
   project's superpowers plans dir (KitnEssentials:
   `dev/docs/superpowers/plans/`; other projects: the superpowers default
   `docs/superpowers/plans/`).

## Mode diff

Same transport and protocol. The brief carries the frozen plan path, the
base/head SHAs superpowers code review used, and the `git diff base..head`
output. Both sides check **spec fidelity** (drift from the frozen plan — the
implementer makes zero judgment calls, so any drift is a finding) and **port
fidelity** (drift from the reference addon), ending PASS / FIX / ESCALATE.

## Finish line

End with one status line: participating models, rounds used, converged vs
escalated points, and DEGRADED if fallbacks.md was in effect.

## Common mistakes

- Accepting Sol's claims about reference code without the cited lines —
  strike the claim per protocol; do not argue against it.
- Re-sending the full debate context each round instead of resuming the
  codex session.
- Running mode `diff` against different SHAs than the code review used.
- Treating convergence as failure — a sound plan converging in one round is
  the system working, not a skipped debate.

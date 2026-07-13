# Frozen plan format

The debate's output is a superpowers-compatible implementation plan. The
implementer (Sonnet 5 or the session model, via superpowers
subagent-driven-development or executing-plans) follows it with **zero
judgment calls** — anything the plan leaves open is a plan defect, found in
mode `diff` as drift.

## Base format

Follow the superpowers writing-plans template exactly (header with Goal /
Architecture / Tech Stack / Global Constraints; bite-sized checkbox tasks
with exact Files / Interfaces / complete code / exact commands / expected
output; no placeholders). Save location follows the project:
KitnEssentials overrides it to
`dev/docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`; other KitnDev
projects use the superpowers default `docs/superpowers/plans/`.

Port-specific Global Constraints to copy in verbatim when they apply:

- KE namespace, flat DB keys, `KE:ApplyFontToText` for SOFTOUTLINE-capable
  text, string literals only — see the module-port skill.
- Reference addon and version the port tracks:
  `References/<addon>/` at the fidelity the debate agreed on (faithful core
  logic; KE-specific deviations listed one per line WITH the debate round
  that approved each).
- WoW 12.0 API constraints the debate verified, each with its citation.

## Debate record appendix (REQUIRED)

Every frozen plan ends with:

```markdown
---

## Debate record

**Participants:** Fable 5 (session) / GPT-5.6 Sol (codex exec, session <id>)
**Rounds used:** N of CAP
**Outcome:** converged | converged with amendments | escalated

### Resolved points
| # | Claim | Raised by | Outcome | Evidence |
|---|-------|-----------|---------|----------|
| 1 | ...   | Sol       | accepted into Task 3 | References/<addon>/<file>:<line> |
| 2 | ...   | Fable     | refuted  | .wow-api-reference/<file> |
| 3 | ...   | Sol       | struck (no citation) | — |

### Escalated points (user-decided)
| # | Question | Fable position | Sol position | Brandon's call |
|---|----------|----------------|--------------|----------------|

### Degraded-mode note
(only if fallbacks.md was in effect — name what was skipped and why)
```

The appendix is the audit trail: mode `diff` re-reads it to know which
deviations were approved and which claims were struck. A frozen plan without
the appendix was not verified — treat it as an unfrozen draft.

## Freezing

A plan is frozen when: both sides verdict PASS — or the final round's FIXes
are accepted on the record (converged with amendments, per
debate-protocol.md) — with any escalations carrying Brandon's recorded
call, the writing-plans self-review checklist has run, and the file is
saved. After freezing, changes require reopening the debate
(a new round appended to the record) — the implementer never edits the plan.

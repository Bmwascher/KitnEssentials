# Fallbacks and degraded modes

Every fallback is VISIBLE: the finish line names the degradation. Silently
skipping cross-vendor review defeats the skill's purpose.

## Preflight failures

### codex CLI missing or broken

`codex --version` fails → **degraded mode**:

1. Report it: "codex unavailable — running degraded (single-vendor) mode."
2. Replace each Sol round with a FRESH-context skeptic subagent (Fable,
   read-only tools). Fresh context is mandatory — same-context self-critique
   rubber-stamps (see model-prompting-notes.md). Brief the skeptic with the
   same XML-style brief Sol would have received, including the strike rule
   and the anti-manufactured-objection rule.
3. The debate record's Participants line reads
   `Fable 5 (session) / Fable 5 skeptic subagent (DEGRADED - codex missing)`.
4. Finish line carries `DEGRADED`.

### Sol model rejected (400 "not supported when using Codex with a ChatGPT account")

The account tier lost Sol access (free/Go tiers get Terra only; Plus and
above get Sol). Do NOT silently substitute another model — Sol is a user
directive. Tell the user, then either wait for them to fix the subscription
or run degraded mode at their choice. Note: `gpt-5.6-terra` responding while
`gpt-5.6-sol` 400s confirms tier-gating, not a CLI problem (probed
2026-07-12).

### codex auth expired

`codex login status` fails → ask the user to run `codex login` interactively
(browser sign-in; cannot be done headless). Degraded mode meanwhile, at
their choice.

## Reference failures

### References/<addon>/ missing

Ask the user for the path. NEVER proceed with an ungrounded debate — a
debate about remembered reference behavior is two models fabricating at each
other. This is a hard stop, not a degraded mode.

### .wow-api-reference/ stale

If the drift check (`lua dev/scripts/update-api-reference.lua`) reports the
build changed under a claim, re-verify that claim before relying on it;
otherwise flag the staleness in the debate record.

## Transport notes

- Session id not found in round-1 output: the header prints
  `session id: <uuid>` — if parsing fails, fall back to fresh
  `codex exec` calls per round with the full brief re-sent (works, costs
  more tokens) and note it in the debate record. Never reach for
  `resume --last` (see model-prompting-notes.md).
- Round timeout: give `codex exec` calls a generous timeout (5-10 min at
  effort high). On timeout, retry once, then degraded mode for the
  remaining rounds.

## Alternative transport (documented, rejected for v1)

CLIProxyAPI (the Theo/Tibo setup) can run Sol as a native Claude Code
subagent by proxying the backend with the same Codex ChatGPT OAuth. Revisit
only if codex exec proves limiting (e.g. Sol needs tool-use inside OUR
harness). It does NOT bypass the subscription tier gate — same auth, same
400 on free accounts. Costs: an always-on local proxy in front of ALL
Claude traffic, Windows service setup, untested cross-vendor hook and
permission semantics.

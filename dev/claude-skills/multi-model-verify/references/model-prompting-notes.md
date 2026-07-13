# Model prompting notes

## Fable 5 (the session side)

From Anthropic's Fable 5 prompting guide (distilled 2026-07; re-check the
guide when it updates):

- **Ground progress claims**: state what was actually run and observed, not
  what should have happened — the guide's grounding pattern nearly eliminated
  fabricated status reports in Anthropic's evals. In debate terms: your
  PASS/FIX verdicts cite the evidence you actually read this session.
- **State the boundaries**: tell the model what is out of scope explicitly.
  The debate brief states what is NOT under debate (already-decided user
  directives, e.g. equal-weight advisors, the chosen reference addon).
- **Fresh-context verification beats self-critique**: Fable reviewing its own
  plan in the same context rubber-stamps. That is the reason Sol exists in
  this loop — and the reason degraded mode (fallbacks.md) must run the
  skeptic pass in a FRESH subagent, not inline.

## GPT-5.6 Sol (the codex side)

- **Outcome-oriented briefs**: tell Sol the outcome to verify, not the steps
  to take. Its codex harness plans its own file reads. OpenAI's guide
  (learn.chatgpt.com/docs/prompting): "Start with the result, not a detailed
  list of steps", and for Codex specifically a useful prompt "names the
  behavior you want, points to the relevant code or reproduction steps,
  preserves important constraints, and says how to verify the change."
- **Four-part shape — Goal, Context, Output, Boundaries** (OpenAI's
  recommended structure; "use only the parts that help"). The XML-style tags
  below map onto it: task=Goal, claims=Context, rules=Output,
  boundaries=Boundaries.
- **Final check** (from the guide's review-task pattern): every brief ends by
  asking Sol to flag information it could NOT verify — those flags feed the
  strike rule instead of masquerading as findings.
- **Structure the brief with XML-style tags**:

  ```text
  <role>Adversarial reviewer, equal weight, in a two-model debate.</role>
  <task>Refute or confirm each numbered claim about the port plan below.</task>
  <rules>Cite References/<addon>/<file>:<line> for every claim you make or
  contest; uncited claims will be struck. Do not manufacture objections:
  if a claim stands, say PASS and move on. End with PASS, FIX (with the
  specific fix), or ESCALATE per claim.</rules>
  <claims>...numbered claims with Fable's citations...</claims>
  <boundaries>...what is already decided and not under debate...</boundaries>
  <final-check>List any claim you could not verify against files you read,
  as UNVERIFIED — do not fold unverified material into your verdict.</final-check>
  ```

- **Effort**: pin `-c model_reasoning_effort=high` per call. Do not use
  ultra/xhigh for debate rounds — Sol propagates its effort to every subagent
  it spawns, which burns tokens without changing verdicts. `high` is also
  set in `~/.codex/config.toml`, but pin it per call anyway so the debate is
  config-independent.
- **Session resume, not context re-send**: capture the `session id:` from
  round 1 and resume it (flags before the subcommand). NEVER `resume --last`
  — it grabs whatever codex session ran most recently, which may be a
  concurrent /codex:review, not your debate.
- **Fabrication counter**: Sol's METR/system-card record means "I verified X"
  claims from Sol get the same strike rule as everything else — quoted
  file:line or it did not happen.

## Reusable recipes

The installed codex plugin ships prompt recipes and antipatterns under its
`gpt-5-4-prompting` skill (plugin cache, `skills/gpt-5-4-prompting/`). They
were written for GPT-5.4-era codex: the structural advice (tight task
framing, no chain-of-thought micromanagement) still applies to Sol, but
verify any model-specific flag or behavior claim against current OpenAI docs
before relying on it.

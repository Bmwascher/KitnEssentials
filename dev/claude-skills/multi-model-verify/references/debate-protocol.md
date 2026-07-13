# Debate protocol

Both advisors are equal weight. Neither model's claim outranks the other's;
only evidence does.

## Evidence grounding (the strike rule)

- Any claim about reference-addon behavior must cite
  `References/<addon>/<file>:<line>` that the citing side actually read
  (Fable: read this session; Sol: read inside its sandboxed run — its quoted
  excerpt counts as reading).
- Any claim about WoW 12.0 API behavior must cite `.wow-api-reference/` or a
  dated in-game probe result.
- A claim with no citation is **struck, not debated**. Note it as struck and
  move on — arguing against an ungrounded claim launders it into the record.
- Reports are claims requiring evidence. "The reference handles this" without
  the file:line is an assertion, not a finding.

## Round structure

Each exchange (one Fable position or rebuttal + one Sol reply) is a round.

1. From round 2 on, state position changes since last round: which of the
   other side's points are **accepted** (absorbed into the plan), which are
   **refuted** (with the evidence that refutes them), which are **struck**
   (no citation).
2. Raise new risks only with evidence attached.
3. End with a verdict on the current plan/diff:
   - **PASS** — no remaining substantive objections.
   - **FIX** — named change required, with the specific fix and its evidence.
   - **ESCALATE** — a disagreement evidence cannot settle (taste, missing
     in-game data, ambiguous reference intent).

## Convergence and the round cap

- Converged: both sides verdict PASS in the same round.
- **Converged with amendments**: the final round's only outstanding verdicts
  are FIXes whose fixes the other side accepts on the record. Record each
  accepted fix in the debate record and treat the plan as converged — an
  accepted FIX is agreement, not a dispute for the user to settle. (This
  matters whenever a FIX lands in the last round before the cap.)
- Round cap: **4 exchanges** by default (caller may raise or lower it).
  Hitting the cap is not failure — it is the signal to stop spending tokens
  on an argument evidence hasn't settled.
- At the cap or on ESCALATE, for points that remain genuinely contested:
  stop, present BOTH positions to the user with their evidence, and let
  Brandon decide. Never silently pick a side.
- In-game verification questions always escalate — neither model can run
  /reload; only Brandon can.

## Anti-sycophancy, anti-theater

Debates fail two ways: rubber-stamping and manufactured conflict. Both are
defects.

- **A sound plan gets one line.** "Plan is sound; the one thing to watch is
  X." Converging in round 1 is the system working.
- **Do not manufacture objections** to justify the round. If you would not
  push back in a real review, do not push back here.
- Do not restate the other side's point in different words as a "new" risk.
- Do not concede a point you can refute just to converge faster —
  unresolved disagreement has an honest exit (ESCALATE).

## Why the structure carries the trust

GPT-5.6 Sol has a documented (METR, OpenAI system card) tendency to fabricate
results under evaluation pressure. The mitigation is this protocol — every
claim must survive citation and refutation by an independent model — not
down-weighting Sol's verdicts. The same rules bind Fable equally: fabricated
detail is a known failure mode of every frontier model, and this project's
history (see memory: no-fabrication feedback) treats invented API behavior as
the cardinal sin.

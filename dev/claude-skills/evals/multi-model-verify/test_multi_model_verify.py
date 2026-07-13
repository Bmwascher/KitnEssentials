"""Deterministic structural tests for the multi-model-verify skill.

Tier 2b: no model calls, no network. Asserts the frozen contract from
dev/docs/superpowers/plans/2026-07-12-multi-model-verify.md so drift in the
skill files fails CI before it misleads a live debate.
"""

import json
import re
from pathlib import Path

import pytest

SKILL_DIR = Path(__file__).resolve().parents[2] / "multi-model-verify"
SKILL_MD = SKILL_DIR / "SKILL.md"
REFERENCES = SKILL_DIR / "references"
EVALS_DIR = Path(__file__).resolve().parent

REQUIRED_REFERENCE_FILES = [
    "debate-protocol.md",
    "frozen-plan-format.md",
    "model-prompting-notes.md",
    "fallbacks.md",
]


def read(path):
    assert path.is_file(), f"missing file: {path}"
    return path.read_text(encoding="utf-8")


def frontmatter(text):
    match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    assert match, "SKILL.md must start with YAML frontmatter"
    return match.group(1)


class TestSkillStructure:
    def test_skill_md_exists(self):
        assert SKILL_MD.is_file()

    def test_frontmatter_name_matches_directory(self):
        fm = frontmatter(read(SKILL_MD))
        name = re.search(r"^name:\s*(\S+)\s*$", fm, re.MULTILINE)
        assert name, "frontmatter needs a name field"
        assert name.group(1) == "multi-model-verify"
        assert re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name.group(1))

    def test_description_is_trigger_only(self):
        fm = frontmatter(read(SKILL_MD))
        desc = re.search(r"^description:\s*(.+)$", fm, re.MULTILINE)
        assert desc, "frontmatter needs a description field"
        text = desc.group(1).strip()
        assert text.startswith("Use when"), "description must start 'Use when'"
        assert len(text) <= 1024
        # Workflow summaries in descriptions shortcut the skill body
        # (superpowers writing-skills SDO finding) - keep them out.
        for banned in ("round", "codex exec", "session id", "freeze"):
            assert banned not in text.lower(), (
                f"description leaks workflow detail: {banned!r}"
            )

    def test_reference_files_exist(self):
        for name in REQUIRED_REFERENCE_FILES:
            assert (REFERENCES / name).is_file(), f"missing references/{name}"

    def test_no_backslash_paths_anywhere(self):
        for path in [SKILL_MD, *(REFERENCES / n for n in REQUIRED_REFERENCE_FILES)]:
            text = read(path)
            assert "\\" not in text, (
                f"{path.name} contains a backslash - use forward slashes and"
                " relative paths only"
            )


class TestTransportContract:
    """The codex invocation shapes were live-verified 2026-07-12 on 0.144.1.

    These strings are load-bearing: get them wrong and debates silently run
    on the wrong model, with write access, or lose cross-round state.
    """

    def test_model_pinned(self):
        text = read(SKILL_MD)
        assert "-m gpt-5.6-sol" in text

    def test_sandbox_read_only(self):
        text = read(SKILL_MD)
        assert "--sandbox read-only" in text

    def test_effort_pinned_high(self):
        joined = read(SKILL_MD) + read(REFERENCES / "model-prompting-notes.md")
        assert "model_reasoning_effort" in joined
        assert '"high"' in joined or "=high" in joined or "effort high" in joined

    def test_resume_flags_before_subcommand(self):
        text = read(SKILL_MD)
        assert re.search(
            r"codex exec --sandbox read-only [^\n]*resume <SESSION_ID>", text
        ), "resume syntax must show flags BEFORE the resume subcommand"
        assert "resume --last" not in text, (
            "resume --last is fragile under concurrent codex sessions and"
            " must not appear in SKILL.md (prohibition lives in"
            " model-prompting-notes.md)"
        )

    def test_session_id_capture_documented(self):
        text = read(SKILL_MD)
        assert "session id" in text.lower()

    def test_reply_captured_to_file(self):
        # codex exec prints a full multi-KB transcript; without this flag the
        # reply is buried at the bottom (live compliance-test finding).
        text = read(SKILL_MD)
        assert "--output-last-message" in text

    def test_versioned_reference_citations(self):
        # References/<addon>/ may hold version subdirectories (e.g. a v1.4/
        # next to a v1.1_old/) - the citation grammar must cover that.
        text = read(SKILL_MD)
        assert "<version>" in text


class TestDebateProtocol:
    def test_round_cap_default(self):
        text = read(REFERENCES / "debate-protocol.md")
        assert re.search(r"round cap.*4|4.*exchanges", text, re.IGNORECASE)

    def test_tri_state_verdict(self):
        text = read(REFERENCES / "debate-protocol.md")
        for verdict in ("PASS", "FIX", "ESCALATE"):
            assert verdict in text

    def test_evidence_grounding_rule(self):
        text = read(REFERENCES / "debate-protocol.md")
        assert "References/" in text
        assert re.search(r"file:line|file and line", text, re.IGNORECASE)

    def test_anti_manufactured_objection_rule(self):
        text = read(REFERENCES / "debate-protocol.md")
        assert re.search(r"manufacture", text, re.IGNORECASE)
        assert re.search(r"sound plan", text, re.IGNORECASE)

    def test_escalation_goes_to_user(self):
        text = read(REFERENCES / "debate-protocol.md")
        assert re.search(r"escalat", text, re.IGNORECASE)

    def test_converged_with_amendments_state(self):
        # A FIX accepted in the final round must not read as disagreement
        # (live compliance-test finding: strict both-PASS convergence
        # overstates conflict when the cap lands on an accepted FIX).
        text = read(REFERENCES / "debate-protocol.md")
        assert re.search(r"converged with amendments", text, re.IGNORECASE)


class TestFallbacks:
    def test_preflight_documented(self):
        text = read(REFERENCES / "fallbacks.md")
        assert "codex --version" in text

    def test_degraded_mode_visible(self):
        text = read(REFERENCES / "fallbacks.md")
        assert re.search(r"degraded", text, re.IGNORECASE)
        assert re.search(r"skeptic", text, re.IGNORECASE)

    def test_missing_reference_refusal(self):
        joined = read(REFERENCES / "fallbacks.md") + read(SKILL_MD)
        assert re.search(r"References/", joined)
        assert re.search(r"ask", joined, re.IGNORECASE)


class TestEvalFixtures:
    def test_trigger_cases_schema(self):
        data = json.loads(read(EVALS_DIR / "trigger-cases.json"))
        assert data["skill"] == "multi-model-verify"
        assert len(data["cases"]) >= 8
        ids = [c["id"] for c in data["cases"]]
        assert len(ids) == len(set(ids)), "case ids must be unique"
        triggers = [c["should_trigger"] for c in data["cases"]]
        assert any(triggers) and not all(triggers), (
            "need both should-trigger and should-not-trigger cases"
        )
        for case in data["cases"]:
            assert case["prompt"].strip()
            assert case["assert"].strip()

    def test_evals_schema(self):
        data = json.loads(read(EVALS_DIR / "evals.json"))
        assert data["skill_name"] == "multi-model-verify"
        assert len(data["evals"]) >= 4
        for entry in data["evals"]:
            assert entry["id"].strip()
            assert entry["prompt"].strip()
            assert entry["expected_output"].strip()
            assert len(entry["expectations"]) >= 3


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))

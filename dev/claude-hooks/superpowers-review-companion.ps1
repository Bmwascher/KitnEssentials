# PostToolUse hook (Task): when the superpowers requesting-code-review skill
# dispatches its code-reviewer subagent, inject a reminder to run the
# multi-model-verify skill's diff mode on the same commit range.
# Fingerprint: the rendered code-reviewer.md template (superpowers 6.1.1)
# always contains the literals "Senior Code Reviewer" and "Git Range to
# Review"; both must be present. Re-check the template after superpowers
# updates - if the fingerprint rots, this hook silently stops firing (fails
# open, never blocks).
# Output contract: silent exit 0 = nothing to add; JSON additionalContext =
# non-blocking context injection.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$prompt = $payload.tool_input.prompt
if (-not $prompt) { exit 0 }

if ($prompt -notmatch 'Senior Code Reviewer') { exit 0 }
if ($prompt -notmatch 'Git Range to Review') { exit 0 }

$base = ''
$head = ''
if ($prompt -match '\*\*Base:\*\*\s*([^\s`\r\n]+)') { $base = $Matches[1] }
if ($prompt -match '\*\*Head:\*\*\s*([^\s`\r\n]+)') { $head = $Matches[1] }
$range = if ($base -and $head) { "base $base head $head" } else { 'the same base/head range the review used' }

$context = "A superpowers code review just ran on this branch ($range). " +
    "If that was the final pre-merge review (requesting-code-review), also run " +
    "the multi-model-verify skill in mode diff on the SAME range now - " +
    "cross-model spec-fidelity and port-fidelity verification is a separate " +
    "gate from single-model code review. If it was an intermediate per-task " +
    "review, defer multi-model-verify until the final review. Skip only if " +
    "mode diff already ran for this exact range."

$out = @{
    hookSpecificOutput = @{
        hookEventName     = 'PostToolUse'
        additionalContext = $context
    }
}
$out | ConvertTo-Json -Compress -Depth 5
exit 0

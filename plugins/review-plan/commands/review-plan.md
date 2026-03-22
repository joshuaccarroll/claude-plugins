Save the current plan to a md file if not already saved. Then use the Task tool to spawn sub-agents to iteratively review and improve it.

## Instructions

1. **Identify the document to review**:
   - If a plan file already exists (e.g., `.claude/current-plan.md`, `PROJECT_*.md`, or another plan document), use that file
   - If the plan content is only in the conversation (e.g., from plan mode), write it to a `.md` file first

2. **Round 1 — Parallel focused lenses** (3 agents simultaneously):

In a **single response**, spawn all 3 Task sub-agents (general-purpose type) simultaneously. Do not wait for one to finish before starting the next.

**Sub-Agent 1 — Technical Soundness:**

Spawn a Task sub-agent (general-purpose type) with this prompt (substitute `[FILE_PATH]` with the actual plan file path):

```
Read [FILE_PATH]. You are reviewing this plan for Technical Soundness only.
Evaluate: Is the scope right? Does the architecture fit? Are steps ordered correctly (foundations before features)? Is each step verifiable? Will any step produce artifacts that strain context windows?

Return your top 3-5 findings in your response. Max 60 lines.
Format: one finding per section with a one-line fix suggestion.
Do NOT modify the plan file. Do NOT create any files. Do NOT explore the codebase — review the plan document only.

If the plan is solid in this lens with no meaningful findings,
respond with exactly: NO_FINDINGS
```

**Sub-Agent 2 — Completeness & Gaps:**

Spawn a Task sub-agent (general-purpose type) with this prompt:

```
Read [FILE_PATH]. You are reviewing this plan for Completeness & Gaps only.
Evaluate: What edge cases are missing? What acceptance criteria are too vague to verify? What prerequisites aren't mentioned? What happens when something fails halfway?

Return your top 3-5 findings in your response. Max 60 lines.
Format: one finding per section with a one-line fix suggestion.
Do NOT modify the plan file. Do NOT create any files. Do NOT explore the codebase — review the plan document only.

If the plan is solid in this lens with no meaningful findings,
respond with exactly: NO_FINDINGS
```

**Sub-Agent 3 — Simplicity & Over-engineering:**

Spawn a Task sub-agent (general-purpose type) with this prompt:

```
Read [FILE_PATH]. You are reviewing this plan for Simplicity & Over-engineering only.
Evaluate: What would you cut to ship in half the time? What abstractions serve hypothetical futures? What could be replaced with a simpler approach?

Return your top 3-5 findings in your response. Max 60 lines.
Format: one finding per section with a one-line fix suggestion.
Do NOT modify the plan file. Do NOT create any files. Do NOT explore the codebase — review the plan document only.

If the plan is solid in this lens with no meaningful findings,
respond with exactly: NO_FINDINGS
```

3. **Apply Round 1 findings** (parent agent — not a sub-agent):

After all 3 sub-agents complete, read the lens responses from the Task tool outputs.

If any sub-agent failed to return a response, log a warning ("Lens agent failed to produce output: [lens name]") and treat as no findings.

For each response that does NOT contain only `NO_FINDINGS`:
- Apply the substantive findings directly to the plan file
- Skip nitpicks and minor style suggestions

4. **Rounds 2-4 — Serial convergence** (up to 3 iterations):

```
iteration = 0
converged = false
while iteration < 3:
    Launch a Task sub-agent (general-purpose type) with this prompt:

    "Read [FILE_PATH]. This plan has already been reviewed and improved in a prior round.
    Your job is to catch only HIGH-IMPACT issues — things that would cause the implementation
    to fail or go significantly wrong.

    Only make changes if you find: a critical missing step, a fundamentally wrong assumption,
    or a dependency ordering that would cause failure. Do NOT make stylistic edits, reword
    for clarity, add minor details, or expand sections that are already adequate.

    If the plan is workable as-is — even if imperfect — respond with exactly: CONVERGED

    Either fix a critical issue in the file or respond CONVERGED. Nothing else."

    if sub-agent output contains "CONVERGED":
        converged = true
        break
    iteration += 1
```

5. **Report results**:
   - How many lens agents produced findings in round 1
   - How many serial iterations ran
   - Whether convergence was reached
   - Summarize the key changes made across all rounds

6. **Structured output** (for automated evaluation):

After completing all rounds and writing your summary report, output exactly this line as the VERY LAST line of your response:

`RESULT: status=[converged|hit_cap|stopped_early] iterations=[N]`

Where:
- `status=converged` — a serial sub-agent responded with CONVERGED before exhausting all 3 serial rounds
- `status=hit_cap` — all 3 serial rounds ran and none responded with CONVERGED
- `status=stopped_early` — you stopped for any other reason (error, no plan file found, etc.)
- `N` = total rounds run. Count the parallel lens round as 1, plus however many serial rounds ran. Maximum is 4 (1 parallel + 3 serial). Minimum is 1 (only the parallel round ran).

This line MUST appear even if something went wrong. It must be the very last line of your entire response, after the summary report.

IMPORTANT: Only the outer orchestrating agent emits this line. Sub-agents spawned via TaskCreate must NOT include "RESULT:" in their output — it is exclusively for the final response of the outer agent.

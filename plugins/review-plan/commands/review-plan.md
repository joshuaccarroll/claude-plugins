Save the current plan to a md file if not already saved. Then use the Task tool to spawn sub-agents to iteratively review and improve it.

## Instructions

1. **Identify the plan file**: Use an existing plan file, or write the plan from the conversation to a `.md` file first.

2. **Round 1 — Parallel lenses**: Spawn 3 Task sub-agents simultaneously, each reviewing the plan through one lens:
   - **Technical Soundness**: scope, architecture, step ordering, verifiability
   - **Completeness & Gaps**: edge cases, vague criteria, missing prerequisites, failure handling
   - **Simplicity**: what to cut, unnecessary abstractions, simpler alternatives

   Each agent reads the plan file and returns findings. If no issues found, responds `NO_FINDINGS`. Agents must NOT modify the plan file.

3. **Apply findings**: Read the sub-agent responses. Apply substantive findings to the plan file. Skip nitpicks.

4. **Rounds 2-6 — Serial convergence** (up to 5 iterations): Spawn one Task sub-agent per round to review the plan with fresh eyes. The agent should fix any issues that would cause implementation to fail — missing steps, vague requirements, incorrect approaches, unhandled failures. It should not bother with wording or style. If the plan is implementable, respond `CONVERGED`. Stop when a sub-agent responds `CONVERGED` or after 5 rounds.

5. **Report**: Summarize findings, iterations, convergence status, and key changes.

6. **Last line of your response** (for automated evaluation):

`RESULT: status=[converged|hit_cap|stopped_early] iterations=[N]`

Where status is `converged`, `hit_cap`, or `stopped_early`, and N is total rounds (1 parallel + serial rounds, max 6). Only the outer agent emits this line — sub-agents must not.

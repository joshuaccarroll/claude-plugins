---
description: Orchestrate multi-step workflows that chain skills and actions with conditional logic. Use when the user defines a pipeline of steps using arrows (->), wants to run multiple skills in sequence, or describes a multi-step process with conditions like "if it converges", "when finished", "if tests pass". Also triggers on "follow these steps", "run this workflow", "chain these", or any ordered list of /skill invocations.
model: opus
---

# Custom Workflow Orchestrator

Execute a user-defined workflow: a sequence of steps that can include skill invocations, conditions, and freeform actions. Parse the workflow, execute each step in order, evaluate conditions between steps, and carry context forward.

## 1. Parse the Workflow

Break the input into an ordered list of steps. Delimiters:
- `->` arrows
- Sequential connectors: "then", "when finished", "after that", "next", "followed by"
- Sentence/clause boundaries between distinct actions

Each step is one of three types:

**Skill invocations** — prefixed with `/` (e.g., `/review-plan`, `/simplify`, `/batch`, `/review`). Execute with the Skill tool. Pass any trailing arguments. Claude Code has many built-in commands beyond what appears in the available skills list — always invoke every `/command` via the Skill tool. Never pre-screen or skip a command because you don't recognize it.

**Conditions** — phrases that gate subsequent steps: "if it converges", "if tests pass", "unless there are errors", "only if successful". Evaluate against the previous step's output.

**Freeform actions** — everything else. Natural language tasks like "approve the plan and build", "run the tests", "fix any issues found". Execute directly using whatever tools fit.

### Passthrough connectors vs real conditions

"When finished", "then", "after that" are not conditions — they just mean "proceed after the previous step completes." Only phrases with genuine uncertainty ("if", "unless", "only when") are conditions.

## 2. Preview Before Executing

Present your interpretation before starting:

```
Parsed workflow:
1. [skill]      /review-plan
2. [condition]  If it converges (gates steps 3-6)
3. [skill]      /batch
4. [action]     Approve the implementation plan and build
5. [skill]      /simplify
6. [skill]      /harmonize
```

Then proceed immediately unless the interpretation is clearly ambiguous. If genuinely ambiguous, ask for clarification.

## 3. Execute Each Step

**CRITICAL: You MUST execute ALL steps in the workflow. Never stop mid-workflow.** After every step completes — especially skill invocations — you MUST continue to the next step. A workflow is not done until the last step is complete. Stopping early is the single most important failure mode to avoid.

### Task tracking

Before executing the first step, create a task for each step using `TaskCreate`. This gives you durable state that survives long-running skills:

```
TaskCreate: "Step 1: /review-plan" (status: in_progress)
TaskCreate: "Step 2: If it converges" (status: pending)
TaskCreate: "Step 3: /batch" (status: pending)
...
```

Mark each task `done` as you complete it. After every step, use `TaskList` to see remaining tasks and continue with the next one.

### Skill invocations

Skill invocations are the most complex step type because the Skill tool loads another skill's instructions into the conversation. After that skill's work completes, you **must** return to this workflow and continue. To stay on track:

1. **Before** invoking a skill, output: `--- WORKFLOW CHECKPOINT: After this skill completes, continue with Step N+1: [description] ---`
2. **Invoke** the skill via the Skill tool
3. **After** it completes, capture the key output (status codes, file paths, errors), then output: `--- Step N complete. Resuming workflow. ---`
4. **Check** `TaskList` to confirm what's next, mark the completed task done, and proceed immediately

### Step execution pattern

For each step:

**Announce**: `--- Step N of M: [brief description] ---`

**Execute**:
- Skills: invoke via the Skill tool with any arguments
- Conditions: evaluate against the previous step's output (see Condition Evaluation below)
- Actions: perform the task directly using available tools

**Report**: brief outcome + `TaskUpdate` to mark done, then immediately proceed to next step.

**REMINDER: After every step, continue to the next. Do not stop. Do not wait for user input unless the step explicitly failed.**

## 4. Condition Evaluation

Evaluate conditions by examining the full output of the preceding step:

- **Convergence**: look for explicit indicators like `status=converged` in the output
- **Success/failure**: did the step complete without errors?
- **Content-based**: does the output satisfy what the condition describes?

When a condition is **not met**: skip all subsequent steps that it gates, explain why, and continue to the next ungated step (if any). This is normal flow, not an error.

### Condition scope

Determine what a condition gates by looking at semantic relatedness, not position:

- A condition gates the steps that are **about** the condition's concern. "If it converges" gates the steps that only make sense when convergence happened (building, deploying, etc.). A final cleanup step like `/harmonize` that applies regardless is ungated.
- When in doubt, look at whether a step makes sense if the condition were false. If `/simplify` would still be useful even if the previous condition failed, it's ungated.
- Explicit scope markers like "otherwise", "regardless", "either way" always break the gate.
- Multiple consecutive conditions stack — all must be met for the steps they gate.

## 5. Context Passing

Carry results forward naturally. You don't need to serialize state — just use what you learned:
- `/review-plan` outputs `RESULT: status=converged iterations=3` — that feeds the next condition
- A build step produces errors — those inform subsequent steps
- File paths and artifacts from one step are available in later steps

## 6. Failure Handling

- **Skill invocation errors**: If the Skill tool returns an error when you invoke a `/command`, report the error and ask whether to continue or stop. Never skip a `/command` preemptively — always attempt it first via the Skill tool, since many commands are built-in to Claude Code and won't appear in any visible skills list.
- **Condition not met**: skip gated steps, explain why, continue to ungated steps — this is expected behavior, not a failure
- **Action fails**: report and ask whether to continue

## 7. Plan Mode & Approval Steps

**Never enter plan mode during workflow execution.** The `EnterPlanMode` and `ExitPlanMode` tools trigger an interactive approval UI in the harness that blocks the workflow and requires manual user intervention. Instead:

- When a step involves planning: explore the codebase, design your approach, write the plan to a markdown file (using the Write tool), and present it inline. Then move to the next step.
- When a step says "approve the plan" (or similar): treat it as an automatic continuation. The user defined the workflow with "approve" in it — that IS the approval. Confirm the plan looks complete and proceed immediately. Do not call `ExitPlanMode` and do not ask for user confirmation.

## Parse Examples

`/review-plan -> If it converges -> approve and build -> /simplify -> /harmonize`

| # | Type | Step | Gated by |
|---|------|------|----------|
| 1 | skill | /review-plan | — |
| 2 | condition | If it converges | — |
| 3 | action | Approve and build | #2 |
| 4 | skill | /simplify | #2 |
| 5 | skill | /harmonize | #2 |

`/simplify -> if there are issues -> fix them -> /harmonize`

| # | Type | Step | Gated by |
|---|------|------|----------|
| 1 | skill | /simplify | — |
| 2 | condition | If there are issues | — |
| 3 | action | Fix them | #2 |
| 4 | skill | /harmonize | — |

Note: step 4 runs regardless — harmonize doesn't depend on whether simplify found issues.

`Plan the migration -> approve the plan -> implement it -> /harmonize`

| # | Type | Step | Gated by |
|---|------|------|----------|
| 1 | action | Plan the migration (write to file, no plan mode — see §7) | — |
| 2 | action | Approve the plan (auto-continue — see §7) | — |
| 3 | action | Implement it | — |
| 4 | skill | /harmonize | — |

Note: steps 1 and 2 follow section 7 rules — the plan is written to a file (never via plan mode) and approval is automatic.

## 8. Never Stop Mid-Workflow

This is the most important rule. After every step — especially after long-running skills like `/review-plan` or `/batch` that spawn sub-agents — you MUST check `TaskList` and continue to the next pending step. The workflow is only complete when all tasks are marked done (or explicitly skipped by a failed condition).

Common failure mode: a skill like `/review-plan` runs for several minutes with multiple iterations. When it finishes, you may feel like you've "completed" something and stop. **Do not stop.** Check your task list and keep going.

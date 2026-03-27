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

**Skill invocations** — prefixed with `/` (e.g., `/review-plan`, `/simplify`). Execute with the Skill tool. Pass any trailing arguments.

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

Skill invocations are the most complex step type because the Skill tool loads another skill's instructions into the conversation. After that skill's work completes, you must return to this workflow and continue with the next step. To stay on track:

- Before invoking a skill, note which step number you're on and what comes next
- After a skill completes, explicitly pick up the workflow: "Step N complete. Continuing workflow — next is Step N+1: [description]"
- Capture the key output from the completed skill (status codes, file paths, errors) since you'll need it for condition evaluation or context in later steps

For each step:

**Announce**: `## Step N: [brief description]`

**Execute**:
- Skills: invoke via the Skill tool with any arguments
- Conditions: evaluate against the previous step's output (see Condition Evaluation below)
- Actions: perform the task directly using available tools

**Report**: brief outcome, then resume the workflow.

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

- **Skill not found**: report it, skip that step, continue (unless subsequent steps depend on it)
- **Skill errors**: report the error, ask whether to continue or stop
- **Condition not met**: skip gated steps, explain why, continue to ungated steps — this is expected behavior, not a failure
- **Action fails**: report and ask whether to continue

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

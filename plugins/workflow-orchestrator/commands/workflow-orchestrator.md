---
description: "Create and execute structured YAML workflows. Use when the user wants to define a multi-step process, chain skills together, or run an existing workflow file. Triggers on: 'workflow', 'create a workflow', 'run this workflow', multi-step instructions with arrows (->), or references to .yaml workflow files."
model: opus
---

# Workflow Orchestrator

You are the **workflow orchestrator** -- a single skill with two primary modes:

1. **Create** -- Transform user instructions into a structured YAML workflow file.
2. **Execute** -- Load a YAML workflow file and run each step in order.

Additionally you support a **list** mode to show saved workflows.

Detect the mode from the user's input. If the input starts with or contains an explicit subcommand (`create`, `run`, `list`), use that. Otherwise auto-detect: if the input looks like a file path or workflow name, treat it as `run`; if it looks like instructions or a description of steps, treat it as `create`.

---

## Mode Detection

| Invocation | Mode |
|---|---|
| `/workflow-orchestrator create <input>` | Create a new workflow from the supplied instructions |
| `/workflow-orchestrator run <name-or-path> [--vars key=value ...]` | Execute an existing workflow YAML file |
| `/workflow-orchestrator list` | List saved workflows in `.claude/workflows/` |
| Ambiguous input that looks like instructions | Create |
| Ambiguous input that looks like a file reference | Run |

**Name resolution for `run`:**
1. If the argument is an absolute or relative path ending in `.yaml`/`.yml`, use it directly.
2. Otherwise look for `.claude/workflows/<name>.yaml`.
3. If not found, look for `.claude/workflows/<name>.yml`.
4. If still not found, report the error and stop.

---

## YAML Workflow Schema Reference

This is the authoritative schema specification. Use it during both create and execute modes.

### Top-Level Structure

```yaml
workflow:
  name: string        # Required. Unique identifier (kebab-case recommended)
  description: string # Optional. Human-readable summary
  version: 1          # Required. Schema version (always 1)
  created: string     # Optional. ISO date string
  vars:               # Optional. Default variable values
    key: value
  steps: [...]        # Required. Ordered list of step objects
```

### Step Types

Every step MUST have an `id` (unique string within its scope) and a `type` field. Additional required and optional fields depend on the type.

#### prompt

Execute a free-form instruction on the main thread.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `prompt` |
| prompt | yes | The instruction text for Claude to execute |
| description | no | Human-readable summary |
| run_in | no | `main` (default) or `agent` |

#### skill

Invoke a registered `/skill` command.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `skill` |
| skill | yes | Skill name (e.g. `review-plan`, `harmonize`) |
| description | no | Human-readable summary |
| args | no | Arguments string to pass to the skill |
| run_in | no | `main` or `agent` (auto-detected if omitted -- see below) |

#### command

Run a shell command and optionally capture output.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `command` |
| run | yes | Shell command string to execute |
| description | no | Human-readable summary |
| output_var | no | Variable name to store stdout into |
| run_in | no | `main` (default) or `agent` |

#### if

Conditional branching.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `if` |
| condition | yes | Expression to evaluate (see Expression Syntax) |
| then | yes | List of steps to run when condition is truthy |
| description | no | Human-readable summary |
| else | no | List of steps to run when condition is falsy |

#### switch

Multi-way branching on a value.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `switch` |
| on | yes | Expression whose result is matched against case keys |
| cases | yes | Map of value -> step list |
| description | no | Human-readable summary |
| default | no | Step list if no case matches |

#### loop

Repeat steps until a condition is met or max iterations reached.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `loop` |
| until | yes | Expression evaluated AFTER each iteration (do-until semantics) |
| max_iterations | yes | Integer or `{{vars.*}}` reference. Hard cap on iterations. |
| steps | yes | List of steps to repeat |
| description | no | Human-readable summary |

#### parallel

Run multiple branches concurrently via simultaneous Agent calls.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `parallel` |
| branches | yes | List of step lists (each branch is its own list of steps) |
| description | no | Human-readable summary |
| barrier | no | Boolean, default `true`. `true` = all branches must succeed; `false` = at least one must succeed. |

#### workflow

Invoke another workflow file (recursive composition).

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `workflow` |
| path | yes | Path to the workflow YAML file |
| description | no | Human-readable summary |
| vars | no | Map of variable overrides to pass to the sub-workflow |

#### create-workflow

Generate a new workflow YAML file from instructions (runs Mode 1 non-interactively).

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `create-workflow` |
| input | yes | Instructions or description for the new workflow |
| output_path | yes | File path to write the generated YAML |
| description | no | Human-readable summary |

#### fail

Immediately stop the workflow with an error message.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `fail` |
| message | yes | Error message to report |
| description | no | Human-readable summary |

---

### Step Outputs and Status

Each completed step has a **status** and optionally an **output**.

**Status values:** `success`, `failed`, `skipped`, `converged`, `timeout`

**Referencing results:**
- `{{steps.<id>.status}}` -- the status string
- `{{steps.<id>.output}}` -- the output value (see below)

**Output by type:**
- `command` -- stdout of the shell command. Also written to `{{vars.<output_var>}}` when `output_var` is set.
- `prompt` -- summary text from Claude's response.
- `skill` -- summary text from the skill's response.
- `create-workflow` -- the path of the generated file. Also available as `{{steps.<id>.output_path}}`.
- Control flow steps (`if`, `switch`, `loop`, `parallel`, `workflow`) -- status reflects the aggregate of contained steps. No direct output value.
- `fail` -- no output; status is always `failed`.

---

### Expression Syntax

Expressions appear in `condition`, `until`, and `on` fields.

**Variable references:**
- `{{vars.name}}` -- workflow variable
- `{{steps.step_id.status}}` -- step status
- `{{steps.step_id.output}}` -- step output

**Comparison operators:** `==`, `!=`, `>`, `<`, `>=`, `<=`

**Boolean operators:** `and`, `or`, `not`

**String matching:** `contains`, `starts_with`
- Example: `{{steps.check.output}} contains 'error'`
- Example: `{{vars.branch}} starts_with 'feature/'`

**String literals:** single-quoted (`'value'`) or bare enum words (`success`, `failed`, `converged`, `skipped`, `timeout`).

**Type coercion:**
- When both sides of a comparison parse as numbers, numeric comparison is used.
- Otherwise, string comparison is used.

**Boolean truthiness:**
- Truthy: `"true"`, `"1"`, any non-empty string
- Falsy: `"false"`, `"0"`, `""` (empty string)

**Loop semantics:**
- `until` is evaluated AFTER each iteration (do-until). The loop body always runs at least once.
- `max_iterations` accepts literal integers or `{{vars.*}}` references.

**Empty step lists:** `[]` is a valid no-op branch (for `then`, `else`, `cases`, `default`, `branches`).

---

### Runtime Variable Overrides

Variables can be overridden at invocation time:

```
/workflow-orchestrator run my-workflow --vars key1=value1 key2=value2
```

**Precedence (highest to lowest):**
1. CLI `--vars` values
2. Parent workflow `vars` (when invoked as a sub-workflow)
3. Defaults in the workflow file's `vars` block

---

### run_in Auto-Detection

When a `skill` step omits `run_in`, the orchestrator detects the correct value:

1. Check if `plugins/<skill-name>/` exists in the repository.
   - If yes: `agent` (custom skill that benefits from isolation)
   - If no: `main` (built-in command that needs full thread context)

For `workflow` steps: scan the referenced workflow for any steps with `run_in: main`. If found, run the sub-workflow on the main thread.

---

## Mode 1: Create Workflow

When in create mode, follow these steps:

### Step 1: Assess Input

Determine whether the input is:
- A **file path** -- read the file and parse its contents as the instructions.
- **Inline text** -- parse the text directly as workflow instructions.

If the input does not describe anything workflow-like (no steps, no sequence, no skill references), stop and alert the user:
> "This input does not appear to describe a multi-step workflow. Please provide a sequence of steps, skill invocations, or a process description."

### Step 2: Extract Steps

Parse the instructions and identify:
- `/skill` invocations (e.g. `/review-plan`, `/harmonize`)
- Shell commands (e.g. `npm test`, `git push`)
- Free-form prompts (e.g. "analyze the codebase for security issues")
- Control flow language (e.g. "if tests pass", "repeat until converged", "do A and B in parallel")
- Failure conditions (e.g. "stop if lint fails")

Map each identified element to the appropriate step type from the schema.

When generating a skill step, check if the skill is known to have `disable-model-invocation` (known bundled skills: `batch`, `debug`) OR if its definition file contains `disable-model-invocation: true` in frontmatter. If so:
1. Warn the user that this skill cannot be invoked programmatically by the orchestrator.
2. Explain the fallback behavior.
3. Offer two choices: **Proceed as-is** (accept runtime fallback) or **Rewrite the step** (use a different step type).

When running non-interactively (as a `create-workflow` step), skip the warning and automatically choose "Proceed as-is."

### Step 3: Fill Gaps (Interactive Only)

When running interactively (invoked directly by the user via `/workflow-orchestrator create`):
- Use `AskUserQuestion` for any ambiguities:
  - Unclear step ordering or dependencies
  - Missing skill arguments
  - Ambiguous control flow ("should this be sequential or parallel?")
  - Variable names or defaults that need clarification

When invoked **non-interactively** as a `create-workflow` step during workflow execution:
- Skip all Q&A.
- Make best-effort assumptions. Prefer sequential over parallel when unclear. Use sensible defaults for missing values.

### Step 4: Detect Execution Context

For each skill step, check the `plugins/` directory:
- If `plugins/<skill-name>/` exists, set `run_in: agent`.
- Otherwise, set `run_in: main`.

For command steps, default to `run_in: main` unless the instructions indicate otherwise.

### Step 5: Generate YAML

Write the workflow to `.claude/workflows/<name>.yaml` where `<name>` is derived from the workflow's purpose (kebab-case, concise).

Ensure the output is valid YAML that conforms to the schema above. Include comments for clarity where helpful.

### Step 6: Explain

Present a summary of the generated workflow:
- Workflow name and file path
- Number of steps
- Step-by-step outline with types and descriptions
- Any assumptions made
- How to execute: `/workflow-orchestrator run <name>`

---

## Mode 2: Execute Workflow

### 2a. Validation

Parse the YAML file and validate against the schema. Check ALL of the following:

1. YAML syntax is valid (parseable)
2. Top-level `workflow` key exists
3. Required top-level fields present: `workflow.name`, `workflow.version`, `workflow.steps`
4. `workflow.version` equals `1`
5. `workflow.steps` is a non-empty list
6. Every step has `id` and `type` fields
7. Every `id` is unique within its scope (top-level, within a loop's steps, within each parallel branch)
8. Every `type` is one of the known types listed in the schema
9. Type-specific required fields are present (e.g. `prompt` steps need `prompt`, `command` steps need `run`, etc.)
10. `run_in` values, when specified, are either `main` or `agent`
11. Variable references in expressions use valid syntax (`{{...}}`)
12. Variable references resolve to declared `vars` or prior step IDs (warn but do not error for runtime vars that may be set dynamically)

**Report ALL validation errors, not just the first one.** Do not proceed to execution if any errors are found.

### 2b. Task Tracking

Create a task for each top-level step using the Task tool:
- Task description includes the step ID, type, and description (or a generated summary)
- Tasks are used to track progress throughout execution

### 2c. Step Execution

Process steps in order. For each step:

**prompt** (run_in: main or default):
Execute the instruction directly on the main thread. Capture the response as the step's output.

**prompt** (run_in: agent):
Spawn a sub-agent with the prompt text using the sub-agent template below.

**command** (run_in: main or default):
Run the shell command using the Bash tool. Capture stdout as the step's output. If `output_var` is set, store the output in `{{vars.<output_var>}}`.

**command** (run_in: agent):
Spawn a sub-agent that executes the shell command.

**skill** -- **CRITICAL: Check the resolved `run_in` value FIRST, then dispatch accordingly. If the YAML explicitly sets `run_in`, use that value. Only auto-detect if `run_in` is omitted.**

**Before dispatching any skill step**, check if the skill is a known non-invocable bundled skill (`batch`, `debug`). If so, skip the Skill tool entirely -- read `plugins/workflow-orchestrator/commands/disable-model-invocation-fallback.md` (resolved relative to git repo root) and follow its instructions.

**skill** (run_in: main):
Invoke the skill directly using `Skill(skill: "<name>", args: "<args>")` on the main thread. This preserves full conversation context. **Do NOT spawn a sub-agent. Do NOT pre-check whether the skill exists. Just call the Skill tool directly.**

**skill** (run_in: agent):
Spawn a sub-agent via the Agent tool. Provide the sub-agent prompt template (see "Sub-Agent Prompt Template" below) with the skill name and args. The sub-agent will call `Skill()` to invoke the skill.

**If the Skill tool returns an error containing `disable-model-invocation`**: do NOT enter self-healing. Read the fallback reference file (`plugins/workflow-orchestrator/commands/disable-model-invocation-fallback.md`) and follow its layered fallback instructions (custom skill filesystem search -> unknown compiled last-resort).

> **`/batch` + `run_in: agent` behavioral exception:** When executing a `/batch` skill step with `run_in: agent`, decomposition always happens on the main thread, then N agents are spawned (one per batch item, not one agent for the entire batch). The orchestrator MUST NOT spawn a single agent for `/batch`.

**if:**
Evaluate the `condition` expression. If truthy, execute the `then` steps. If falsy and `else` is defined, execute the `else` steps. The if-step's status is the aggregate of whichever branch ran (or `skipped` if no branch ran).

**switch:**
Evaluate the `on` expression. Match the result against `cases` keys. Execute the matching case's steps. If no match and `default` is defined, execute default steps. Status is aggregate of executed branch.

**loop:**
1. Execute the `steps` list.
2. Evaluate the `until` expression.
3. If truthy, stop looping. The loop status is `converged`.
4. If falsy and iteration count < `max_iterations`, go to step 1.
5. If falsy and iteration count >= `max_iterations`, stop. The loop status is `failed`.

**parallel:**
Spawn ALL branches simultaneously by making multiple Agent tool calls in a single message. Each branch is forced to `run_in: agent` regardless of individual step settings. All Agent calls are issued together and resolve concurrently.

- `barrier: true` (default): all branches must succeed for the parallel step to succeed.
- `barrier: false`: at least one branch must succeed.

If a branch contains steps that require `run_in: main` and fails because of it, apply self-healing: after the parallel block completes, retry the failed branch sequentially on the main thread.

**create-workflow:**
Run Mode 1 (Create) non-interactively. Skip Q&A. Use the `input` field as instructions and write the result to `output_path`. Validate the generated YAML immediately. If validation fails, attempt one self-healing retry.

**workflow:**
Load the referenced YAML file. Validate it. Execute it recursively with any `vars` overrides merged (CLI > parent vars > file defaults). The sub-workflow's final status becomes this step's status.

**fail:**
Immediately stop workflow execution. Report the `message`. Mark this step and the overall workflow as `failed`.

### 2d. Progress Monitoring

**Sub-agent progress logs:**
Sub-agents write progress to `$TMPDIR/wf-<workflow-name>-<step-id>.log` using the format specified in the sub-agent template.

**Agent calls are blocking.** The orchestrator cannot poll sub-agents mid-execution. Progress logs are read AFTER the agent returns and used for:
- Reporting via TaskUpdate
- Diagnosing failures or timeouts
- Providing context to subsequent steps

**Main-thread steps** report progress inline in real-time since they execute directly in the conversation.

### 2e. Self-Healing

After a step completes or times out, apply the appropriate recovery strategy:

> **`disable-model-invocation` errors are NOT retryable.** If a skill step's error contains `disable-model-invocation`, do NOT retry. Instead, read `plugins/workflow-orchestrator/commands/disable-model-invocation-fallback.md` (resolved relative to git repo root) and follow the layered fallback instructions. This is handled by the skill dispatch logic above and should never reach self-healing, but this clause serves as a safety net.

**Error (step returned failure):**
1. Read the error message and the step's progress log (if it ran as an agent).
2. Analyze the root cause.
3. Attempt one fix (e.g. install a missing dependency, correct a path, adjust an argument).
4. Retry the step once.
5. If the retry also fails, mark the step as `failed` and continue to the next step.

**Timeout (agent did not return in time):**
1. Read the progress log for the last recorded milestone.
2. Mark the step as `timeout`.
3. Continue with remaining steps (they may still succeed without this step's output).

**Main-thread failure:**
1. Read the error output.
2. Fix inline (e.g. correct a command, adjust a prompt).
3. Retry once.
4. If retry fails, mark as `failed` and continue.

**Unrecoverable:**
If a step fails after retry and the failure is clearly unrecoverable (e.g. missing required tool, permission denied, referenced file does not exist), alert the user clearly with:
- The step ID and type
- The error message
- The progress log contents (if available)
- What was attempted for recovery
- Suggestion for manual resolution

---

## Error Propagation Rules

These rules govern how failures propagate through the workflow:

1. **Loop `max_iterations` exceeded:** The loop's status is `failed`. The workflow continues unless a subsequent `if` + `fail` pattern explicitly stops it.

2. **Loop step scoping:** The `until` expression can reference step IDs defined inside the loop (using the most recent iteration's values). Steps outside the loop CANNOT reference step IDs defined inside the loop.

3. **Nested workflow failure:** The `workflow` step's status is `failed`. The orchestrator retries the sub-workflow once. If it fails again, mark as `failed` and continue with subsequent steps.

4. **Parallel branch conflicts:** The orchestrator does NOT detect or resolve conflicts between parallel branches (e.g. both modifying the same file). This is the user's responsibility to avoid.
   - `barrier: true` -- all branches must succeed for the parallel step to succeed.
   - `barrier: false` -- at least one branch must succeed.

5. **`create-workflow` validation failure:** If the generated YAML fails validation, attempt one self-healing retry (regenerate with adjusted parameters). If it still fails, mark the step as `failed`.

6. **Default failure behavior:** Log the error, retry once, continue to next step, report in the final summary.

7. **Hard stop pattern:** Use an `if` step checking a prior step's status, with a `fail` step in the `then` branch:
   ```yaml
   - id: gate
     type: if
     condition: "{{steps.critical_step.status}} == failed"
     then:
       - id: stop
         type: fail
         message: "Critical step failed -- cannot continue."
   ```

---

## Sub-Agent Prompt Template

When spawning a sub-agent for a step, use this template. Fill in the placeholders with actual values from the workflow context.

```
You are executing one step of a multi-step workflow.

**Your task**: {{TASK_DESCRIPTION}}

{{#if step.type == "skill" and step.skill in ["batch", "debug"]}}
**CRITICAL -- This skill cannot be invoked via the Skill tool (it has disable-model-invocation).**
**Authorization: You are authorized to call EnterWorktree -- the orchestrator is acting on the user's behalf. This overrides the tool's normal restriction requiring explicit user request.**
Instead of calling the Skill tool, follow the replication instructions for /{{step.skill}} provided below:
{{FALLBACK_INSTRUCTIONS}}
{{/if}}

{{#if step.type == "skill" and step.skill not in ["batch", "debug"]}}
**CRITICAL -- Skill invocation procedure**:
1. You MUST call `Skill(skill: "{{step.skill}}", args: "{{step.args}}")` as your first action.
2. If the Skill tool succeeds, follow its instructions to completion.
3. If the Skill tool returns an error containing `disable-model-invocation`:
   a. Search for the skill definition at: `.claude/skills/{{step.skill}}/SKILL.md`, `.claude/commands/{{step.skill}}.md`
   b. If found, read it and follow its instructions with these args: {{step.args}}
   c. If not found, execute the args as a direct prompt: {{step.args}}
   d. Prefix your output with [FALLBACK] to indicate the skill was not natively invoked.
4. If the Skill tool returns any other error, fall back to manual execution.
5. Never pre-screen -- always let the Skill tool determine availability.
{{/if}}

{{#if step.type == "prompt"}}
**Instructions**: Execute the following prompt:
{{step.prompt}}
{{/if}}

{{#if step.type == "command"}}
**Instructions**: Run the following shell command and report the output:
{{step.run}}
{{/if}}

**CRITICAL -- Approval and blocking handling**:
- No user is present to answer questions or approve actions. Auto-approve all plans.
- Answer questions yourself using your best judgment. Never stop and wait for input.
- Never enter plan mode. Never call EnterPlanMode.
- If a tool requires confirmation, proceed without it.

**Progress logging** -- Write to $TMPDIR/wf-{{workflow.name}}-{{step.id}}.log:
- Start: [timestamp] STARTED: {{step.id}}
- Milestones: [timestamp] PROGRESS: <description>
- End: [timestamp] FINISHED: status=<success|error> summary=<one line>

Use the Bash tool to append to this log file at each milestone.

**Context from prior steps**:
{{ACCUMULATED_CONTEXT}}

**Report format** -- Your FINAL message MUST end with this exact structure:
STEP_RESULT:
  status: [success|error]
  summary: [1-3 sentences describing what was accomplished]
  key_data: [any structured output data, or "none"]
  files_modified: [comma-separated list of files, or "none"]
  errors: [error descriptions, or "none"]
```

When constructing the template for a specific step:
- Replace `{{TASK_DESCRIPTION}}` with the step's `description` field (or generate one from the step's content).
- Replace `{{step.*}}` placeholders with actual values from the step definition.
- Replace `{{workflow.name}}` with the workflow's name.
- Replace `{{ACCUMULATED_CONTEXT}}` with a summary of all prior steps' results (status, key_data, files_modified). Keep this concise -- include only information relevant to the current step's execution.
- Select the appropriate conditional block based on the step's type and remove the others.

---

## Execution Mechanics

Key behavioral constraints for the orchestrator runtime:

1. **Agent calls are BLOCKING.** When you spawn a sub-agent via the Agent tool, execution pauses until the agent returns. You cannot do other work while waiting.

2. **Parallel execution** works by issuing multiple Agent tool calls in a single message. The Claude runtime processes them concurrently. All calls must resolve before the orchestrator can continue.

3. **`barrier: false` does NOT enable early exit.** Even with `barrier: false`, all branches run to completion. The only difference is how failure is assessed: with `barrier: true`, any branch failure fails the parallel step; with `barrier: false`, only total failure (all branches fail) fails the parallel step.

4. **Progress logs are post-hoc diagnostics.** Sub-agents write to log files, but the orchestrator cannot read them until the agent returns. Logs are used for failure diagnosis and reporting, not real-time monitoring.

5. **Real-time reporting** is only available for main-thread steps (those with `run_in: main` or default). These steps execute inline and their progress is visible immediately.

6. **Variable interpolation** happens just before each step executes. All `{{...}}` references in a step's fields are resolved using the current state of `vars` and `steps` at that point in execution.

7. **Step ID scoping:** Top-level steps can reference any prior top-level step's results. Steps inside a loop, if-branch, or parallel branch can reference both their local siblings and any prior top-level steps. Outer steps cannot reference IDs defined inside control flow blocks.

---

## Inline Example

A simple linear workflow that plans, reviews, builds, and explains:

```yaml
workflow:
  name: plan-review-build
  description: Generate a plan, review it, implement it, then explain the changes
  version: 1
  vars:
    goal: "Add input validation to the API endpoints"
    max_review_rounds: 5
  steps:
    - id: plan
      type: prompt
      description: Create an implementation plan
      prompt: >
        Analyze the codebase and create a detailed plan for: {{vars.goal}}.
        Save the plan to plan.md.

    - id: review
      type: skill
      description: Iteratively review and refine the plan
      skill: review-plan
      args: "plan.md"

    - id: check-review
      type: if
      description: Ensure the review converged before proceeding
      condition: "{{steps.review.status}} == converged"
      then:
        - id: build
          type: prompt
          description: Implement the plan
          prompt: >
            Read plan.md and implement all changes described in it.
            Follow the plan exactly. Run tests after each major change.
        - id: lint
          type: command
          description: Run the linter
          run: "npm run lint --fix"
        - id: harmonize
          type: skill
          description: Harmonize new code with codebase conventions
          skill: harmonize
        - id: explain
          type: skill
          description: Explain what was built
          skill: explain
          args: "Explain the changes made to implement input validation"
      else:
        - id: review-failed
          type: fail
          message: "Plan review did not converge after {{vars.max_review_rounds}} rounds. Review manually."
```

### Execution trace for this example:

1. **plan** runs on main thread. Claude analyzes the codebase and writes `plan.md`.
2. **review** auto-detects `run_in: agent` (since `plugins/review-plan/` exists). A sub-agent invokes `/review-plan` which iteratively refines `plan.md`.
3. **check-review** evaluates whether the review converged.
   - If `converged`: executes the `then` branch (build, lint, harmonize, explain).
   - If not: executes the `else` branch which triggers a `fail` step and stops the workflow.
4. **build** runs on main thread. Claude implements the plan.
5. **lint** runs `npm run lint --fix` via Bash and captures output.
6. **harmonize** auto-detects `run_in: agent`. A sub-agent runs `/harmonize`.
7. **explain** auto-detects `run_in: agent`. A sub-agent runs `/explain`.
8. Orchestrator prints the completion summary table.

---

## Mode 3: List Workflows

When in list mode:

1. Scan the `.claude/workflows/` directory for `.yaml` and `.yml` files.
2. For each file, parse the YAML and extract `workflow.name` and `workflow.description`.
3. Present a table:

| Name | Description | File |
|---|---|---|
| plan-review-build | Generate a plan, review it, implement it... | .claude/workflows/plan-review-build.yaml |

If the directory does not exist or contains no workflow files, report that no workflows are saved and suggest using `/workflow-orchestrator create` to make one.

---

## Completion Summary Format

After a workflow finishes execution (whether fully successful or partially), present a summary:

```
## Workflow Complete: <workflow-name>

| Step | Type | Status | Duration | Files Modified |
|------|------|--------|----------|----------------|
| plan | prompt | success | 45s | plan.md |
| review | skill | converged | 2m 15s | plan.md |
| build | prompt | success | 3m 02s | src/api/validate.ts, src/api/routes.ts |
| lint | command | success | 8s | src/api/validate.ts |
| harmonize | skill | success | 1m 30s | src/api/validate.ts |
| explain | skill | success | 20s | none |

**Overall status:** success
**Total duration:** 7m 40s
**Files modified:** plan.md, src/api/validate.ts, src/api/routes.ts
```

If any steps failed or were skipped, highlight them clearly and include error summaries.

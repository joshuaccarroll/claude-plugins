# Execution Reference

Detailed rules for Mode 2 (Execute Workflow). Read this when executing any workflow.

---

## Validation Checklist

Parse the YAML file and validate ALL of the following before execution:

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

**Report ALL validation errors, not just the first one.** Do not proceed if any errors are found.

---

## Step Dispatch Rules

### prompt

- `run_in: main` (default): Execute the instruction directly on the main thread. Capture the response as step output.
- `run_in: agent`: Spawn a sub-agent with the prompt text using the sub-agent template (`references/sub-agent-template.md`).

### command

- `run_in: main` (default): Run via Bash tool. Capture stdout as step output. If `output_var` is set, store in `{{vars.<output_var>}}`.
- `run_in: agent`: Spawn a sub-agent that executes the shell command.

### skill

**Check the resolved `run_in` value FIRST, then dispatch. If YAML explicitly sets `run_in`, use that. Only auto-detect if omitted.**

**Before dispatching**, check if the skill is a known non-invocable bundled skill (`batch`, `debug`). If so, skip the Skill tool entirely -- read `references/fallback.md` and follow its instructions.

- `run_in: main`: Call `Skill(skill: "<name>", args: "<args>")` directly on main thread. Do NOT spawn a sub-agent. Do NOT pre-check skill existence.
- `run_in: agent`: Spawn a sub-agent via Agent tool using the sub-agent template. The sub-agent calls `Skill()`.

**If the Skill tool returns an error containing `disable-model-invocation`**: do NOT self-heal. Read `references/fallback.md` and follow its layered fallback instructions.

**`/batch` + `run_in: agent` exception:** Decomposition always happens on the main thread, then N agents are spawned (one per batch item, not one agent for the entire batch).

### if

Evaluate the `condition` expression. If truthy, execute `then` steps. If falsy and `else` is defined, execute `else` steps. Status is the aggregate of whichever branch ran (or `skipped` if no branch ran).

### switch

Evaluate the `on` expression. Match result against `cases` keys. Execute the matching case's steps. If no match and `default` is defined, execute default. Status is aggregate of executed branch.

### loop

1. Execute the `steps` list.
2. Evaluate the `until` expression.
3. If truthy, stop. Loop status is `converged`.
4. If falsy and iteration count < `max_iterations`, go to step 1.
5. If falsy and iteration count >= `max_iterations`, stop. Loop status is `failed`.

### parallel

Spawn ALL branches simultaneously by making multiple Agent tool calls in a single message. Each branch is forced to `run_in: agent` regardless of individual step settings.

- `barrier: true` (default): all branches must succeed for the parallel step to succeed.
- `barrier: false`: at least one branch must succeed.

If a branch contains steps that require `run_in: main` and fails because of it, apply self-healing: after the parallel block completes, retry the failed branch sequentially on the main thread.

### workflow

Load the referenced YAML file. Validate it. Execute recursively with any `vars` overrides merged (CLI > parent vars > file defaults). The sub-workflow's final status becomes this step's status.

### create-workflow

Run Mode 1 (Create) non-interactively. Skip Q&A. Use `input` as instructions and write to `output_path`. Validate the generated YAML immediately. If validation fails, attempt one self-healing retry.

### fail

Immediately stop workflow execution. Report the `message`. Mark this step and the overall workflow as `failed`.

---

## Progress Monitoring

**Sub-agent progress logs:** Sub-agents write to `$TMPDIR/wf-<workflow-name>-<step-id>.log` using the format in the sub-agent template.

**Agent calls are blocking.** The orchestrator cannot poll sub-agents mid-execution. Progress logs are read AFTER the agent returns and used for:
- Reporting via TaskUpdate
- Diagnosing failures or timeouts
- Providing context to subsequent steps

**Main-thread steps** report progress inline in real-time.

---

## Self-Healing

After a step fails or times out:

> **`disable-model-invocation` errors are NOT retryable.** If a skill step's error contains `disable-model-invocation`, read `references/fallback.md` instead. This should be caught by dispatch logic above, but serves as a safety net.

**Error (step returned failure):**
1. Read the error message and the step's progress log (if it ran as an agent).
2. Analyze the root cause.
3. Attempt one fix (e.g. install a missing dependency, correct a path, adjust an argument).
4. Retry the step once.
5. If the retry also fails, mark the step as `failed` and continue.

**Timeout (agent did not return):**
1. Read the progress log for the last recorded milestone.
2. Mark the step as `timeout`.
3. Continue with remaining steps.

**Main-thread failure:**
1. Read the error output.
2. Fix inline (e.g. correct a command, adjust a prompt).
3. Retry once.
4. If retry fails, mark as `failed` and continue.

**Unrecoverable:** If a step fails after retry and is clearly unrecoverable (missing tool, permission denied, referenced file does not exist), alert the user with: the step ID/type, error message, progress log, what was attempted, and a suggestion for manual resolution.

---

## Error Propagation Rules

1. **Loop `max_iterations` exceeded:** Loop status is `failed`. Workflow continues unless a subsequent `if` + `fail` pattern explicitly stops it.

2. **Loop step scoping:** `until` can reference step IDs defined inside the loop (most recent iteration's values). Steps outside the loop CANNOT reference IDs defined inside.

3. **Nested workflow failure:** `workflow` step's status is `failed`. Retry the sub-workflow once. If it fails again, mark `failed` and continue.

4. **Parallel branch conflicts:** The orchestrator does NOT detect or resolve conflicts between parallel branches (e.g. both modifying the same file). User's responsibility.
   - `barrier: true` -- any branch failure fails the parallel step.
   - `barrier: false` -- only total failure (all branches fail) fails the parallel step.

5. **`create-workflow` validation failure:** Attempt one self-healing retry (regenerate). If still fails, mark `failed`.

6. **Default failure behavior:** Log error, retry once, continue to next step, report in final summary.

7. **Hard stop pattern:** Use an `if` step checking a prior step's status with a `fail` step in the `then` branch:
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

## Execution Mechanics

1. **Agent calls are BLOCKING.** Execution pauses until the agent returns.

2. **Parallel execution** works by issuing multiple Agent tool calls in a single message. All calls must resolve before continuing.

3. **`barrier: false` does NOT enable early exit.** All branches run to completion. The only difference is failure assessment.

4. **Progress logs are post-hoc diagnostics.** Cannot be read until the agent returns.

5. **Real-time reporting** is only available for main-thread steps.

6. **Variable interpolation** happens just before each step executes. All `{{...}}` references are resolved using the current state of `vars` and `steps`.

7. **Step ID scoping:** Top-level steps can reference any prior top-level step's results. Steps inside a loop, if-branch, or parallel branch can reference both local siblings and prior top-level steps. Outer steps cannot reference IDs defined inside control flow blocks.

---
name: workflow-orchestrator
description: "Create and execute structured YAML workflows. Use when the user wants to define a multi-step process, chain skills together, or run an existing workflow file. Triggers on: 'workflow', 'create a workflow', 'run this workflow', multi-step instructions with arrows (->), or references to .yaml workflow files."
model: opus
---

# Workflow Orchestrator

Four modes:

1. **Create** -- Transform user instructions into a structured YAML workflow file.
2. **Execute** -- Load a YAML workflow file and run each step in order.
3. **List** -- Show saved workflows.
4. **Help** -- Print a friendly, comprehensive guide for new users.

---

## Mode Detection

| Invocation | Mode |
|---|---|
| `/workflow-orchestrator create <input>` | Create |
| `/workflow-orchestrator run <name-or-path> [--vars key=value ...]` | Execute |
| `/workflow-orchestrator list` | List |
| `/workflow-orchestrator help` | Help |
| Ambiguous input resembling instructions | Create |
| Ambiguous input resembling a file reference | Run |

**Name resolution for `run`:**
1. If the argument is a path ending in `.yaml`/`.yml`, use it directly.
2. Otherwise look for `.claude/workflows/<name>.yaml`, then `.yml`.
3. If not found, report the error and stop.

---

## Mode 1: Create Workflow

Read `references/schema.md` before generating any workflow YAML.

1. **Assess Input** -- File path (read it) or inline text. If it doesn't describe a multi-step process, tell the user.

2. **Extract Steps** -- Identify skill invocations, shell commands, free-form prompts, control flow ("if tests pass", "repeat until", "in parallel"), and failure conditions. Map each to the appropriate step type from the schema.

3. **Check for Non-Invocable Skills** -- If a step targets a `disable-model-invocation` skill (`batch`, `debug`, or any with that frontmatter flag):
   - Interactive: warn user, offer "Proceed as-is" or "Rewrite the step"
   - Non-interactive (`create-workflow` step): proceed as-is automatically

4. **Fill Gaps** (interactive only) -- Use `AskUserQuestion` for ambiguities (ordering, missing args, parallel vs sequential). Non-interactive: best-effort assumptions.

5. **Detect `run_in`** -- For each skill step, check if `plugins/<skill-name>/` exists:
   - Yes: `run_in: agent` | No: `run_in: main`
   - Commands default to `run_in: main`

6. **Generate YAML** -- Write to `.claude/workflows/<name>.yaml`. Valid YAML conforming to the schema. Add comments where helpful.

7. **Explain** -- Present: workflow name, file path, step count, step outline, assumptions, how to run it.

---

## Mode 2: Execute Workflow

Read `references/execution.md` for the full validation checklist, step dispatch rules, self-healing strategy, and error propagation semantics. Read `references/sub-agent-template.md` when spawning any sub-agent.

### High-Level Flow

1. **Validate** -- Parse YAML, run 12-point validation (details in `references/execution.md`). Report ALL errors. Do not proceed if any exist.

2. **Create Tasks** -- One task per top-level step (ID, type, description).

3. **Execute Steps** in order:

   | Step Type | Behavior |
   |---|---|
   | **prompt** / **command** | Main thread (default) or sub-agent if `run_in: agent` |
   | **skill** | Check `run_in` (YAML explicit > auto-detect). `main`: call `Skill()` directly. `agent`: spawn sub-agent with template |
   | **skill** (non-invocable) | Skip Skill tool. Read `references/fallback.md`, follow layered fallback |
   | **if** / **switch** | Evaluate condition/expression, execute matching branch |
   | **loop** | Do-until: run steps, evaluate `until`, repeat or stop at `max_iterations` |
   | **parallel** | Spawn ALL branches simultaneously via concurrent Agent calls |
   | **workflow** | Load, validate, execute recursively with var overrides |
   | **create-workflow** | Run Mode 1 non-interactively |
   | **fail** | Stop immediately with error message |

4. **Self-Heal** on failure: analyze error, attempt one fix, retry once. `disable-model-invocation` errors are NOT retryable -- use `references/fallback.md` instead.

5. **Report** completion summary (see below).

### Key Execution Rules

- Agent calls are **blocking**. Parallel execution = multiple Agent calls in one message.
- Variable interpolation (`{{...}}`) happens just before each step executes.
- Step ID scoping: top-level steps reference any prior; nested steps reference locals + prior top-level.
- `barrier: true` (default) = all parallel branches must succeed. `barrier: false` = at least one.
- Progress logs: `$TMPDIR/wf-<name>-<step-id>.log` -- post-hoc diagnostics only.
- If Skill tool returns `disable-model-invocation` error: do NOT self-heal. Read `references/fallback.md`.
- `/batch` with `run_in: agent`: decomposition always on main thread, then N agents (one per item, not one for entire batch).

---

## Mode 3: List Workflows

Scan `.claude/workflows/` for `.yaml`/`.yml` files. Parse each and present:

| Name | Description | File |
|---|---|---|
| example | Description... | .claude/workflows/example.yaml |

If none found, suggest `/workflow-orchestrator create`.

---

## Mode 4: Help

When the user runs `/workflow-orchestrator help`, read `references/user-guide.md` and print its contents **exactly as written** (do not summarize, truncate, or rephrase). Output it as a single markdown message.

---

## Completion Summary

After execution, present:

```
## Workflow Complete: <name>

| Step | Type | Status | Duration | Files Modified |
|------|------|--------|----------|----------------|
| ...  | ...  | ...    | ...      | ...            |

**Overall status:** success|failed
**Total duration:** Xm Ys
**Files modified:** file1, file2
```

Highlight any failed/skipped steps with error summaries.

---

## Reference Files

Read these as needed during workflow creation and execution:

| File | When to Read |
|---|---|
| `references/schema.md` | Before creating workflow YAML; during validation |
| `references/execution.md` | When executing (validation, dispatch, self-healing, errors) |
| `references/sub-agent-template.md` | When spawning a sub-agent for any step |
| `references/examples.md` | For example workflows and execution traces |
| `references/fallback.md` | When a skill has `disable-model-invocation` |
| `references/user-guide.md` | When the user runs `/workflow-orchestrator help` |

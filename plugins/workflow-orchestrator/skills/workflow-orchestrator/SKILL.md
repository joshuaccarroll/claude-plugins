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

When the user runs `/workflow-orchestrator help`, print the guide below **exactly as written** (do not summarize, truncate, or rephrase). Output it as a single markdown message:

````markdown
# Workflow Orchestrator -- User Guide

## What this solves

You probably already chain skills and commands together by hand:
*plan something, review it, build it, lint, test, explain...*

The workflow orchestrator lets you **save that entire sequence as a YAML file** and replay it with one command. Think of it as a recipe: you write it once, then run it whenever you need it.

**Why bother?**
- **Repeatable** -- the same steps run the same way every time.
- **Hands-free** -- long pipelines run without you babysitting each step.
- **Shareable** -- drop a `.yaml` file in your repo and anyone with this skill can run it.
- **Composable** -- workflows can call other workflows, run steps in parallel, branch on conditions, and loop until done.

---

## Quick start (< 2 minutes)

### 1. Create a workflow from plain English

```
/workflow-orchestrator create Plan a CLI tool, review the plan, build it, then explain what was built
```

This generates a `.yaml` file in `.claude/workflows/` and shows you what it created.

### 2. Run it

```
/workflow-orchestrator run <workflow-name>
```

That's it. The orchestrator walks through every step, tracks progress, and prints a summary when it finishes.

### 3. See what you have

```
/workflow-orchestrator list
```

Lists all saved workflows with their names and descriptions.

---

## The four commands

| Command | What it does |
|---|---|
| `create <instructions>` | Turns your description into a YAML workflow file |
| `run <name> [--vars key=value ...]` | Executes a saved workflow |
| `list` | Shows all workflows in `.claude/workflows/` |
| `help` | Prints this guide |

**Shorthand:** You can often skip the subcommand. If your input looks like instructions, it creates. If it looks like a file name, it runs.

---

## How a workflow file is structured

```yaml
workflow:
  name: my-workflow           # kebab-case identifier
  description: What it does   # optional but helpful
  version: 1                  # always 1
  vars:                       # default variables (optional)
    greeting_count: 50
  steps:                      # the ordered list of things to do
    - id: plan
      type: prompt
      prompt: "Plan a tool that prints {{vars.greeting_count}} greetings"

    - id: build
      type: prompt
      prompt: "Build the tool described in the plan"

    - id: test
      type: command
      run: "npm test"
```

**Key ideas:**
- `vars` are defaults you can override at runtime with `--vars`.
- `{{vars.name}}` inserts a variable's value anywhere in a step.
- `{{steps.plan.status}}` and `{{steps.plan.output}}` let later steps react to earlier ones.

---

## Step types at a glance

| Type | Purpose | Example |
|---|---|---|
| `prompt` | Ask Claude to do something | `prompt: "Refactor the auth module"` |
| `skill` | Run a slash command | `skill: review-plan` |
| `command` | Run a shell command | `run: "npm test"` |
| `if` | Do something only when a condition is true | `condition: "{{steps.test.status}} == success"` |
| `switch` | Pick a path based on a value | `on: "{{vars.language}}"` with cases for `python`, `typescript`, etc. |
| `loop` | Repeat until a condition is met | `until: "{{vars.count}} >= 100"` |
| `parallel` | Run multiple things at the same time | Two or more branches that don't depend on each other |
| `workflow` | Call another workflow file | `path: ".claude/workflows/deploy.yaml"` |
| `fail` | Stop everything with an error | `message: "Tests failed -- aborting"` |
| `create-workflow` | Generate a new workflow on the fly | `input: "instructions..."` |

---

## Practical patterns

### Override variables at runtime

```
/workflow-orchestrator run build-tool --vars tool_name=hello-world greeting_count=10
```

Variable precedence (highest wins): CLI `--vars` > parent workflow vars > file defaults.

### Stop the workflow if something critical fails

```yaml
- id: gate
  type: if
  condition: "{{steps.tests.status}} == failed"
  then:
    - id: stop
      type: fail
      message: "Tests failed -- cannot continue to deploy."
```

Without this, a failed step is logged but the workflow keeps going.

### Run independent work in parallel

```yaml
- id: quality
  type: parallel
  branches:
    - steps:
        - id: lint
          type: command
          run: "npm run lint"
    - steps:
        - id: typecheck
          type: command
          run: "npm run typecheck"
```

Both branches run at the same time. By default all must succeed (`barrier: true`).

### Loop until done

```yaml
- id: generate
  type: loop
  until: "{{vars.item_count}} >= 100"
  max_iterations: 20
  steps:
    - id: batch
      type: prompt
      prompt: "Generate the next batch of items"
    - id: count
      type: command
      run: "wc -l items.txt | tr -d ' '"
      output_var: item_count
```

The loop body always runs at least once (do-until semantics).

### Chain workflows together

```yaml
- id: deploy
  type: workflow
  path: ".claude/workflows/deploy.yaml"
  vars:
    env: production
```

The sub-workflow runs with its own variables, merged with whatever you pass in.

---

## Expression cheat sheet

Use these in `condition`, `until`, and `on` fields:

| Expression | Meaning |
|---|---|
| `{{steps.X.status}} == success` | Step X succeeded |
| `{{steps.X.output}} contains 'error'` | Step X's output includes "error" |
| `{{vars.branch}} starts_with 'feature/'` | Variable starts with a prefix |
| `{{vars.count}} >= 10` | Numeric comparison |
| `A and B` | Both conditions true |
| `A or B` | Either condition true |
| `not A` | Condition is false |

---

## What happens when something fails

The orchestrator tries to be resilient:

1. **Automatic retry** -- if a step fails, it reads the error, tries to fix it, and retries once.
2. **Continue by default** -- after a failed retry, the step is marked `failed` but the workflow continues.
3. **Hard stops are opt-in** -- use the `if` + `fail` pattern above to make a failure halt the workflow.
4. **Full summary at the end** -- you always get a table showing every step's status, duration, and files modified.

---

## Where to look next

- **Example workflows** in `.claude/workflows/examples/`:
  - `01-simple-linear.yaml` -- straightforward plan-build-explain pipeline
  - `02-moderate-with-logic.yaml` -- conditionals, loops, and switch statements
  - `03-complex-full-featured.yaml` -- parallel execution, nested workflows, dynamic generation
- **Create your first workflow** -- just run `/workflow-orchestrator create` and describe what you want in plain English.
````

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

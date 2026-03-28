# Workflow Orchestrator -- User Guide

## What this solves

You probably already chain skills and commands together by hand:
*plan something, review it, build it, lint, test, explain...*

The workflow orchestrator lets you **save that entire sequence as a YAML file** and replay it with one command. Think of it as a recipe: you write it once, then run it whenever you need it.

**Why bother?**
- **Repeatable** -- the same steps run the same way every time.
- **Hands-free** -- long pipelines run without you babysitting each step.
- **Shareable** -- drop a `.yaml` file in your repo and anyone with this skill can run it.
- **Global or local** -- save workflows to a single project or make them available everywhere.
- **Composable** -- workflows can call other workflows, run steps in parallel, branch on conditions, and loop until done.

---

## Quick start (< 2 minutes)

### 1. Create a workflow from plain English

```
/workflow-orchestrator create Plan a CLI tool, review the plan, build it, then explain what was built
```

You'll be asked whether to save it **locally** (this project only) or **globally** (available in all projects).

### 2. Run it

```
/workflow-orchestrator run <workflow-name>
```

That's it. The orchestrator walks through every step, tracks progress, and prints a summary when it finishes.

### 3. See what you have

```
/workflow-orchestrator list
```

Lists all saved workflows (both local and global) with their names, scope, and descriptions.

---

## The four commands

| Command | What it does |
|---|---|
| `create <instructions>` | Turns your description into a YAML workflow file |
| `run <name> [--vars key=value ...]` | Executes a saved workflow |
| `list` | Shows all workflows (local and global) |
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

## Local vs global workflows

Workflows can live in two places:

| Scope | Location | When to use |
|---|---|---|
| **Local** | `.claude/workflows/` (in your project) | Project-specific pipelines, shareable with teammates via git |
| **Global** | `~/.claude/workflows/` (in your home directory) | Personal workflows you want available in every project |

When you `create` a workflow, you'll be asked which scope to use. When you `run` a workflow by name, the orchestrator checks local first, then global. If both exist with the same name, local wins.

---

## Where to look next

- **Example workflows** in `.claude/workflows/examples/`:
  - `01-simple-linear.yaml` -- straightforward plan-build-explain pipeline
  - `02-moderate-with-logic.yaml` -- conditionals, loops, and switch statements
  - `03-complex-full-featured.yaml` -- parallel execution, nested workflows, dynamic generation
- **Create your first workflow** -- just run `/workflow-orchestrator create` and describe what you want in plain English.

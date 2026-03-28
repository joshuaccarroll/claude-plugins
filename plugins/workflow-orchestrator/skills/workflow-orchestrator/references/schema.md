# YAML Workflow Schema Reference

Authoritative schema specification. Use during both create and execute modes.

## Top-Level Structure

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

## Step Types

Every step MUST have an `id` (unique string within its scope) and a `type` field.

### prompt

Execute a free-form instruction.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `prompt` |
| prompt | yes | The instruction text for Claude to execute |
| description | no | Human-readable summary |
| run_in | no | `main` (default) or `agent` |

### skill

Invoke a registered `/skill` command.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `skill` |
| skill | yes | Skill name (e.g. `review-plan`, `harmonize`) |
| description | no | Human-readable summary |
| args | no | Arguments string to pass to the skill |
| run_in | no | `main` or `agent` (auto-detected if omitted) |

### command

Run a shell command and optionally capture output.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `command` |
| run | yes | Shell command string to execute |
| description | no | Human-readable summary |
| output_var | no | Variable name to store stdout into |
| run_in | no | `main` (default) or `agent` |

### if

Conditional branching.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `if` |
| condition | yes | Expression to evaluate (see Expression Syntax) |
| then | yes | List of steps to run when condition is truthy |
| description | no | Human-readable summary |
| else | no | List of steps to run when condition is falsy |

### switch

Multi-way branching on a value.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `switch` |
| on | yes | Expression whose result is matched against case keys |
| cases | yes | Map of value -> step list |
| description | no | Human-readable summary |
| default | no | Step list if no case matches |

### loop

Repeat steps until a condition is met or max iterations reached.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `loop` |
| until | yes | Expression evaluated AFTER each iteration (do-until semantics) |
| max_iterations | yes | Integer or `{{vars.*}}` reference. Hard cap on iterations. |
| steps | yes | List of steps to repeat |
| description | no | Human-readable summary |

### parallel

Run multiple branches concurrently via simultaneous Agent calls.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `parallel` |
| branches | yes | List of step lists (each branch is its own list of steps) |
| description | no | Human-readable summary |
| barrier | no | Boolean, default `true`. `true` = all must succeed; `false` = at least one. |

### workflow

Invoke another workflow file (recursive composition).

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `workflow` |
| path | yes | Path to the workflow YAML file |
| description | no | Human-readable summary |
| vars | no | Map of variable overrides to pass to the sub-workflow |

### create-workflow

Generate a new workflow YAML file from instructions (runs Mode 1 non-interactively).

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `create-workflow` |
| input | yes | Instructions or description for the new workflow |
| output_path | yes | File path to write the generated YAML |
| description | no | Human-readable summary |

### fail

Immediately stop the workflow with an error message.

| Field | Required | Description |
|---|---|---|
| id | yes | Unique step identifier |
| type | yes | `fail` |
| message | yes | Error message to report |
| description | no | Human-readable summary |

---

## Step Outputs and Status

Each completed step has a **status** and optionally an **output**.

**Status values:** `success`, `failed`, `skipped`, `converged`, `timeout`

**Referencing results:**
- `{{steps.<id>.status}}` -- the status string
- `{{steps.<id>.output}}` -- the output value

**Output by type:**
- `command` -- stdout. Also written to `{{vars.<output_var>}}` when `output_var` is set.
- `prompt` -- summary text from Claude's response.
- `skill` -- summary text from the skill's response.
- `create-workflow` -- path of the generated file. Also available as `{{steps.<id>.output_path}}`.
- Control flow (`if`, `switch`, `loop`, `parallel`, `workflow`) -- status reflects aggregate of contained steps. No direct output value.
- `fail` -- no output; status is always `failed`.

---

## Expression Syntax

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
- When both sides parse as numbers, numeric comparison is used.
- Otherwise, string comparison.

**Boolean truthiness:**
- Truthy: `"true"`, `"1"`, any non-empty string
- Falsy: `"false"`, `"0"`, `""` (empty string)

**Loop semantics:**
- `until` is evaluated AFTER each iteration (do-until). The loop body always runs at least once.
- `max_iterations` accepts literal integers or `{{vars.*}}` references.

**Empty step lists:** `[]` is a valid no-op branch (for `then`, `else`, `cases`, `default`, `branches`).

---

## Runtime Variable Overrides

Variables can be overridden at invocation time:

```
/workflow-orchestrator run my-workflow --vars key1=value1 key2=value2
```

**Precedence (highest to lowest):**
1. CLI `--vars` values
2. Parent workflow `vars` (when invoked as a sub-workflow)
3. Defaults in the workflow file's `vars` block

---

## run_in Auto-Detection

When a `skill` step omits `run_in`:

1. Check if `plugins/<skill-name>/` exists in the repository.
   - If yes: `agent` (custom skill that benefits from isolation)
   - If no: `main` (built-in command that needs full thread context)

For `workflow` steps: scan the referenced workflow for any steps with `run_in: main`. If found, run the sub-workflow on the main thread.

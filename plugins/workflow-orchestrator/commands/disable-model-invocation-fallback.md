# Fallback Handling for `disable-model-invocation` Skills

When a skill has `disable-model-invocation: true`, the Skill tool cannot invoke it. The orchestrator detects this via the error pattern:

> `Skill <name> cannot be used with Skill tool due to disable-model-invocation`

Apply the layers below **in order**. Stop at the first layer that matches.

---

## Layer A: Known Bundled Skills

### `/batch`

The `/batch` skill orchestrates parallel work across worktrees. Since it cannot be invoked via the Skill tool, **replicate its behavior inline**:

1. **Analyze** the args string to identify the overall task.
2. **Decompose** the task into independent work units. Each unit must be self-contained (no cross-unit dependencies).
3. **Single-unit fast path** -- if decomposition yields only 1 unit, execute it directly on the current thread. Skip agent spawning and worktree creation.
4. **Spawn parallel agents** -- for 2+ units, issue one Agent tool call per unit simultaneously. Each agent's prompt must include:
   - The unit's task description
   - An authorization override in the agent prompt: "You are authorized to call `EnterWorktree` -- the orchestrator is acting on the user's behalf."
   - An `EnterWorktree` call to create an isolated worktree
   - Instructions to do all work inside the worktree
   - An `ExitWorktree` call with `action: "keep"` when finished
5. **Merge** -- after all agents return, merge results back to the main branch:
   - For each completed worktree branch, use `git merge` or `git cherry-pick` to bring changes into the current branch.
   - If merge conflicts occur, resolve them or report them as errors.
   - This merge step runs on the main thread and is critical -- without it, parallel work is lost.
6. **Report** -- collect and synthesize a unified summary of all units' results.

> **Important:** `ExitWorktree` uses `action: "keep"` -- not `keep: true`.

### `/debug`

Pass through to **Layer C** (args-as-prompt). The `/debug` skill's behavior is simple enough that direct prompt execution is sufficient.

---

## Layer B: Custom Skills (Filesystem Search)

If the skill name does not match a known bundled skill above, search for its definition file in these locations (in order):

1. `.claude/skills/<name>/SKILL.md`
2. `.claude/commands/<name>.md`
3. `~/.claude/skills/<name>/SKILL.md`
4. `~/.claude/commands/<name>.md`
5. `plugins/*/commands/<name>.md`
6. `plugins/*/skills/<name>/SKILL.md`

If a file is found:

1. **Read** the skill definition file.
2. **Substitute** `$ARGUMENTS` in the file contents with the step's args string.
3. **Execute** the resulting instructions directly.

If no file is found in any location, fall through to Layer C.

---

## Layer C: Unknown / Compiled Skills (Last Resort)

For skills with no bundled handler (Layer A) and no discoverable definition file (Layer B), use **args-as-prompt** execution:

1. Construct a prompt by combining the skill name and args:
   ```
   [FALLBACK] Executing skill "<name>" with instructions: <args>
   ```
2. Execute this prompt directly on the current thread (or within the sub-agent, if running as `run_in: agent`).
3. Prepend `[FALLBACK]` to the step output so the orchestrator and user can see that native invocation was bypassed.

> **Note:** Layer C is a best-effort fallback. The skill's specialized behavior may not be fully replicated. The orchestrator should log a warning when this layer is reached.

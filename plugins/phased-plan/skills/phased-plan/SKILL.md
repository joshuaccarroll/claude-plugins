---
description: Draft a high-level, phased plan using the skates → skateboard → bicycle → car philosophy. Saves to ~/.claude/plans/<plan-name>.md and hands off to /plan-phase.
disable-model-invocation: true
argument-hint: [concept]
allowed-tools: Read Write Bash(mkdir *) Bash(ls *) Bash(test *)
model: opus
---

The concept to plan: $ARGUMENTS

If `$ARGUMENTS` is empty, ask the user for a concept and stop.

Make a high-level, phased plan. Think functional, vertical implementation iterations: skates, then a skateboard, then a bicycle, then a car rather than frame, then wheels, then the engine, etc. Each phase should be independently testable and verifiable.

Process:

1. If the concept is unclear or missing key details, ask 1–3 clarifying questions before drafting.
2. Draft the phased plan. For each phase include:
   - **Goal** — the working slice of value this phase delivers (vertical, not horizontal).
   - **Scope** — what's in, what's deferred to later phases.
   - **Verification** — how this phase is independently tested; what "done" looks like.
   - **Dependencies** — what must be true going in; what unlocks the next phase.
3. Pick a short kebab-case `<PLAN_NAME>` derived from the concept (e.g., `cli-todo-list`, not `CLI Todo List`).
4. Ensure the plans directory exists: `mkdir -p ~/.claude/plans`.
5. Check whether `~/.claude/plans/<PLAN_NAME>.md` already exists (e.g., `test -f ~/.claude/plans/<PLAN_NAME>.md`). If it does, ask the user whether to overwrite or pick a new name; do not silently overwrite.
6. Write the plan to `~/.claude/plans/<PLAN_NAME>.md` using the Write tool.
7. Show the plan to the user, then ask: "Ready to save and hand off, or want changes?". If they request changes, apply them, re-save the file, and ask again. Stop iterating when the user says some variant of "looks good", "ship it", "save it", "done", or "approved". If their response is ambiguous, ask once more rather than guessing.
8. Once the user approves, end your response with the following two lines as the very last lines of your message. Substitute the actual kebab-case name for `<PLAN_NAME>`:

   Plan saved to ~/.claude/plans/<PLAN_NAME>.md. Clear context with /clear, then run:
   /plan-phase <PLAN_NAME> 1

   Do NOT write "Here is the handoff:" or any preamble before these lines. Do NOT wrap them in a code fence. Do NOT add any text, blank lines, or punctuation after them. They are the literal final two lines of your message.

Do not begin implementation. The deliverable of this skill is the saved plan file plus the handoff message.

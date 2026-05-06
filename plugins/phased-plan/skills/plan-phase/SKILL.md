---
description: Create a detailed implementation plan for one phase of a saved phased plan, then implement it with TDD at the seams and adversarial verification.
disable-model-invocation: true
argument-hint: <plan-name> <phase-number>
allowed-tools: Read Write Edit Task Glob Grep Bash(ls *) Bash(test *)
model: opus
---

Plan name: `$0`
Phase number: `$1`

Create an implementation plan for Phase $1 of `~/.claude/plans/$0.md`. Architect for deep modules with simple interfaces and use TDD principles to test at the seams. Include a verification step in which you spin up adversarial agents to test as much as possible, fixing any issues, before handing it to me with instructions for how I can manually verify the outcome for myself.

Process:

1. **Validate args.** If `$0` is empty, ask the user for the plan name and stop. If `$1` is empty or not a positive integer, ask the user for the phase number and stop.
2. **Locate the plan file.** Check that `~/.claude/plans/$0.md` exists (via `test -f` or by attempting to Read it). If not, list the contents of `~/.claude/plans/` so the user can see available plans, and stop.
3. **Read the plan in full.** Locate the section for Phase $1. If that phase doesn't exist (e.g., the plan only has 3 phases and the user asked for 7), list the available phases by name/number and stop.
4. **Draft a detailed implementation plan for Phase $1:**
   - **Module design** — identify the seams and what each module hides behind a narrow interface.
   - **TDD at the seams** — for each seam, list the test cases that prove the contract before any production code is written.
   - **Phase boundary** — confirm the phase satisfies its parent verification criteria standalone, without depending on later phases.
5. **Write a Verification section into the plan document** describing the verification approach. This is plan text, not execution. Two parts:
   - **Adversarial verification** — describe what the post-implementation adversarial pass will check (edge cases, error paths, fuzzed inputs, integration gaps, regressions in adjacent code). Do NOT spawn sub-agents at this point — that happens in step 7.
   - **Manual verification handoff** — concrete checklist for the user: commands to run, things to click, expected outputs.
6. **Present the plan to the user for approval.** Do not implement until they explicitly approve.
7. **Implement the phase, then run adversarial verification.** Once approved, you (this same agent, in this same session) implement the phase. After implementation, **now** spawn sub-agents using the Task tool to execute the adversarial pass described in step 5. Address every issue they surface before declaring the phase complete.
8. **Hand off.** After the phase is implemented and verified, end your response with one of the two blocks below as the very last lines of your message. Substitute the actual values for `$0`, `$1`, and the next phase number.

   If there is a next phase in the plan:

   Phase $1 of $0 complete. Clear context with /clear, then run:
   /plan-phase $0 <next-phase-number>

   If this was the final phase of the plan:

   Phase $1 of $0 complete. This was the final phase of the plan.

   Do NOT write "Here is the handoff:" or any preamble. Do NOT wrap the lines in a code fence. Do NOT add text, blank lines, or punctuation after them. They are the literal final lines of your message.

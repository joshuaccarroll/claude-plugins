# Example Workflows

## plan-review-build

A linear workflow that plans, reviews, builds, and explains:

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

### Execution Trace

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

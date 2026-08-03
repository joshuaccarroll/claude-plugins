# Claude Code Plugins

A plugin marketplace for [Claude Code](https://claude.ai/code) — productivity skills for planning, reviewing, and orchestrating work.

## Setup

```bash
# 1. Add the marketplace
claude plugins marketplace add joshuaccarroll-plugins --source github --repo joshuaccarroll/claude-plugins

# 2. Install the plugins you want
claude plugins install review-plan@joshuaccarroll-plugins
claude plugins install harmonize@joshuaccarroll-plugins
claude plugins install explain@joshuaccarroll-plugins
claude plugins install workflow-orchestrator@joshuaccarroll-plugins
claude plugins install phased-plan@joshuaccarroll-plugins
claude plugins install real-talk@joshuaccarroll-plugins
claude plugins install josh-slack-voice@joshuaccarroll-plugins
```

## Skills

All plugins are implemented as skills — directly invocable via slash command (`/skill-name`) and also triggered contextually by Claude when relevant to your conversation.

| Skill | What it does |
|---|---|
| `/review-plan` | Iteratively reviews a plan using sub-agents until convergence |
| `/harmonize` | Harmonizes changed code with surrounding codebase patterns |
| `/explain` | Explains code or concepts in succinct, plain language |
| `/workflow-orchestrator` | Creates and executes structured YAML workflows |
| `/phased-plan` | Drafts a high-level, phased plan and saves it to `~/.claude/plans/` |
| `/plan-phase` | Designs and implements one phase of a saved phased plan with TDD + adversarial verification |
| `/real-talk` | Responds in succinct, plain, casual language |
| `/josh-slack-voice` | Drafts Slack messages in Josh's writing voice (drafts only, never sends) |

### `/review-plan` — Plan Reviewer

Spawns a fresh sub-agent for each review pass (up to 5). Each agent reads the plan, identifies gaps, and saves improvements directly. Repeats until convergence or the iteration cap.

**Checks for:** missing steps, vague requirements, unhandled edge cases, incorrect technical approaches, missing error handling.

### `/harmonize` — Code Harmonizer

Identifies recently changed code via git, discovers conventions from sibling files and CLAUDE.md, and applies minimal edits where changed code diverges from established patterns. Skips ambiguous cases and never changes behavior.

### `/explain` — Plain English Explainer

Explains code or concepts in succinct, plain language. Pass it a file, function, concept, or question.

### `/workflow-orchestrator` — Workflow Orchestrator

Saves multi-step processes as YAML files and replays them with one command. Supports prompts, skills, shell commands, conditionals, loops, parallel execution, and nested workflows.

```bash
# Create a workflow from plain English
/workflow-orchestrator create Plan the feature, review it, build it, then explain

# Run a saved workflow
/workflow-orchestrator run my-workflow

# List all workflows
/workflow-orchestrator list
```

Workflows can be saved **locally** (`.claude/workflows/` — project-specific) or **globally** (`~/.claude/workflows/` — available in all projects). Run `/workflow-orchestrator help` for the full guide.

### `/phased-plan` & `/plan-phase` — Phased Build Workflow

A two-skill workflow for building anything in vertical, independently-verifiable phases (skates → skateboard → bicycle → car).

1. `/phased-plan <concept>` drafts a high-level phased plan and saves it to `~/.claude/plans/<plan-name>.md`.
2. After approving the plan, run `/clear` to start a fresh context, then `/plan-phase <plan-name> 1` to design and implement Phase 1 with TDD at the seams and adversarial-agent verification.
3. Repeat with `/clear` between phases until the plan is done.

Both skills are user-invocation only (`disable-model-invocation: true`) — Claude won't auto-trigger them mid-conversation.

### `/real-talk` — Plain Language Responses

Makes Claude respond in succinct, casual, plain language: short sentences, answer first, no preamble, no em-dashes, no formatting clutter. Plain doesn't mean vague — accuracy still matters.

### `/josh-slack-voice` — Personal Slack Voice

Drafts Slack messages in Josh's own voice: his diction, structure, and length instincts. Triggers on "write this in my voice", "draft a Slack message", "make this sound like me", or pasting a rough draft to clean up. It always drafts into a fenced code block for copy/paste and flags what it assumed or invented — it never sends or schedules anything.

This one is personal, so it won't be much use to you as-is. The transferable part is the architecture:

| File | Loading | Contains |
|---|---|---|
| `SKILL.md` | always | Rules, forms, invariants, anti-patterns |
| `references/edits.md` | always | Hand-rewrites of the skill's own drafts, strikethrough for cuts |
| `references/corpus.md` | by section | Example messages grouped by register |

`edits.md` does the heavy lifting. Rules derived from a corpus get the *register* right; watching what someone deletes from a draft gets the *voice* right. The corpus is split out and read by section rather than whole, which keeps per-invocation context around a third of what a single flat file cost.

To fork it for yourself: replace the corpus with your own messages, then every time the skill produces something that isn't quite you, rewrite it by hand and add the before/after to `edits.md`. That feedback loop improved output more than any rule I wrote.

Every situation, figure, vendor, tool, channel, and name in the reference files is invented. They're there to demonstrate sentence shape, not to describe anything real.

## Contributing

Add a new plugin by creating a directory under `plugins/`:

```
plugins/my-plugin/
├── .claude-plugin/
│   └── plugin.json      # Plugin metadata (required)
└── skills/
    └── my-skill/
        └── SKILL.md     # Skill definition (slash command + contextual trigger)
```

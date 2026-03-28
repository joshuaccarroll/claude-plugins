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
```

## Plugins

| Command | What it does |
|---|---|
| `/review-plan` | Iteratively reviews a plan using sub-agents until convergence |
| `/harmonize` | Harmonizes changed code with surrounding codebase patterns |
| `/explain` | Explains code or concepts in succinct, plain English |
| `/workflow-orchestrator` | Creates and executes structured YAML workflows |

### `/review-plan` — Plan Reviewer

Spawns a fresh sub-agent for each review pass (up to 5). Each agent reads the plan, identifies gaps, and saves improvements directly. Repeats until convergence or the iteration cap.

**Checks for:** missing steps, vague requirements, unhandled edge cases, incorrect technical approaches, missing error handling.

### `/harmonize` — Code Harmonizer

Identifies recently changed code via git, discovers conventions from sibling files and CLAUDE.md, and applies minimal edits where changed code diverges from established patterns. Skips ambiguous cases and never changes behavior.

### `/explain` — Plain English Explainer

Explains code or concepts in succinct, plain English. Pass it a file, function, concept, or question.

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

## Contributing

Add a new plugin by creating a directory under `plugins/`:

```
plugins/my-plugin/
├── .claude-plugin/
│   └── plugin.json      # Plugin metadata (required)
├── commands/             # Slash commands (optional)
├── agents/               # Agent definitions (optional)
└── skills/               # Skill/knowledge modules (optional)
```

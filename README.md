# Claude Code Plugins

Personal plugin marketplace for [Claude Code](https://claude.ai/code).

## Plugins

### `/review-plan` — Plan Reviewer

Iteratively reviews and improves an implementation plan using sub-agents. Spawns a fresh sub-agent for each review pass (up to 5), where each agent reads the plan, identifies gaps or areas for improvement, and saves changes directly to the plan file. Repeats until the plan converges (no more substantive issues found) or hits the iteration cap.

**What it checks for:** Missing steps, vague requirements, unhandled edge cases, incorrect technical approaches, missing error handling — anything that would cause a developer to get stuck during implementation.

**Output:** A summary of findings, iterations completed, and convergence status.

### `/harmonize` — Code Harmonizer

Reviews recently changed code and harmonizes it with the patterns, conventions, and style of the surrounding codebase. Reads sibling files to discover established conventions, checks CLAUDE.md for explicit rules, and applies minimal edits only where the changed code clearly diverges from consistent patterns. Skips ambiguous cases and never changes behavior.

### `/explain` — Plain English Explainer

Explains code or concepts in succinct, plain English.

## Installation

This marketplace is registered in `~/.claude/plugins/known_marketplaces.json` as `claude-plugins-joshuaccarroll`. Plugins are available automatically in Claude Code sessions.

To add a new plugin, create a directory under `plugins/` following this structure:

```
plugins/my-plugin/
├── .claude-plugin/
│   └── plugin.json      # Plugin metadata (required)
├── commands/             # Slash commands (optional)
├── agents/               # Agent definitions (optional)
└── skills/               # Skill/knowledge modules (optional)
```

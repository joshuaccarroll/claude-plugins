# Claude Code Plugins

Personal plugin marketplace for [Claude Code](https://claude.ai/code).

## Plugins

### `/harmonize` — Code Harmonizer

Reviews recently changed code and harmonizes it with the patterns, conventions, and style of the surrounding codebase. Ensures new code looks like it was written by the same team that wrote the rest of the repo.

**How it works:**
1. Identifies changed files via `git diff`
2. Reads 3-5 sibling files to discover established conventions (naming, structure, error handling, imports, etc.)
3. Checks CLAUDE.md for explicit conventions (which always take precedence)
4. Applies targeted edits to align divergent code with surrounding patterns
5. Skips ambiguous cases — when the codebase itself is inconsistent, it does nothing

**Safety:** Changes are purely cosmetic/structural. Never alters behavior, propagates anti-patterns, or reduces type safety.

### `/review-plan` — Plan Reviewer

Iteratively reviews the current plan using sub-agents. Spawns up to 5 review passes, each critically examining the plan for gaps and improvements, until the plan reaches convergence.

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

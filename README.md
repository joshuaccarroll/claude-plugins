# Claude Code Plugins

Personal plugin marketplace for [Claude Code](https://claude.ai/code).

## Plugins

### `/harmonize` — Code Harmonizer

Reviews recently changed code and harmonizes it with the patterns, conventions, and style of the surrounding codebase. Ensures new code looks like it was written by the same team that wrote the rest of the repo.

**How it works:**
1. Identifies changed code via `git diff` (unstaged, staged, or last commit) and reads both the full files and the diffs to know exactly which sections are new or modified
2. Reads 3-5 sibling files and imported dependencies to discover established conventions (naming, structure, error handling, control flow, imports, comments, type annotations, testing patterns)
3. Checks CLAUDE.md for explicit conventions (which always take precedence over observed patterns)
4. Flags only clear divergences where 3+ surrounding files agree on a pattern and the changed code deviates — skips ambiguous cases where the codebase itself is inconsistent
5. Runs safety checks before each edit (see below)
6. Applies targeted, minimal edits to only the divergent sections
7. Summarizes: files modified, patterns addressed, and any divergences intentionally skipped with reasons

**Safety checks — every edit must pass all of these:**
- Does not change behavior (purely cosmetic/structural)
- Does not propagate anti-patterns from surrounding code
- Does not violate SOLID/DRY principles
- Does not reduce type safety or remove error handling
- CLAUDE.md wins any conflict with observed patterns

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

---
description: Harmonize changed code with surrounding codebase patterns
allowed-tools: Read, Edit, Glob, Grep, Bash(git:*)
model: opus
---

Harmonize recently changed code so it matches the patterns, conventions, and style of the surrounding codebase. The goal is consistency — changed code should look like it was written by the same team that wrote the rest of the codebase.

Follow these steps precisely:

## Step 1: Identify changed code

Run these git commands to find changed files:

1. `git diff --name-only` (unstaged changes)
2. `git diff --cached --name-only` (staged changes)
3. If both are empty, fall back to `git diff HEAD~1 --name-only` (last commit)

If not in a git repo or no changes are found, report clearly and stop.

Read the full content of each changed file. Also run `git diff` (or `git diff --cached`, or `git diff HEAD~1`) to see the actual changes so you know which sections are new or modified.

## Step 2: Discover surrounding patterns

For each changed file, read 3-5 sibling files in the same directory. Prefer shorter, representative files of the same type. Also read files that the changed file imports or requires.

From these sibling files, extract the established conventions for:

- **Naming**: casing style, prefixes, suffixes, abbreviation conventions
- **Function/method structure**: ordering, grouping, length patterns
- **Error handling**: approach (early returns, rescue blocks, try/catch, Result types)
- **Control flow**: early returns vs nested conditionals
- **Import/require ordering**: stdlib vs third-party vs local, alphabetical vs grouped
- **Comment and documentation patterns**: style, frequency, placement
- **Type annotations**: presence, style, specificity
- **Testing patterns**: if test files are among the changed files, examine sibling test files for describe/context structure, setup patterns, assertion style

## Step 3: Check CLAUDE.md

Search for and read any CLAUDE.md files that apply to the changed files — the repo root CLAUDE.md and any CLAUDE.md files in parent directories of the changed files. Explicit conventions in CLAUDE.md always take precedence over patterns observed in surrounding code.

## Step 4: Identify disharmony

Compare the changed code against the discovered patterns. Flag only clear, unambiguous divergences where:

- The surrounding codebase is internally consistent on that pattern (3+ files agree)
- The changed code clearly deviates from that consistent pattern

If the codebase itself is inconsistent on a pattern (e.g., mixed naming styles), do **nothing** for that category. When in doubt, skip.

## Step 5: Safety checks

Before applying any change, verify ALL of the following:

- **Does not change behavior**: The edit is purely cosmetic/structural. No logic changes, no reordering of side effects, no altered return values.
- **Does not propagate anti-patterns**: If surrounding code has a bad pattern (e.g., swallowing exceptions, god methods, magic numbers), do NOT harmonize toward it.
- **Does not violate SOLID/DRY**: Do not introduce duplication or break single-responsibility just for consistency.
- **Does not reduce type safety**: Do not remove type annotations or weaken types.
- **Does not remove error handling**: Do not strip error handling even if surrounding code lacks it.
- **CLAUDE.md wins conflicts**: If CLAUDE.md says one thing but surrounding code does another, follow CLAUDE.md.

If a change fails any of these checks, skip it.

## Step 6: Apply edits

Use the Edit tool to apply each harmonization change directly. Make targeted, minimal edits — change only what diverges from the established pattern.

## Step 7: Summarize

After all edits are applied, provide a concise summary:

- **Files modified**: List each file you edited
- **Patterns addressed**: For each file, briefly describe what was harmonized (e.g., "renamed `getUserData` to `get_user_data` to match snake_case convention")
- **Intentionally skipped**: Note any divergences you noticed but deliberately left alone, and why (e.g., "Mixed import ordering across sibling files — no clear convention to follow")

If no changes were needed, say so clearly: "All changed code already matches surrounding codebase patterns. No harmonization needed."

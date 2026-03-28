---
name: harmonize
description: "Harmonize changed code with surrounding codebase patterns. Use this skill whenever the user wants to align recently changed code with existing conventions, fix style inconsistencies, or make new code match the rest of the codebase — even if they say 'clean up', 'make it consistent', or 'match the style'."
allowed-tools: Read, Edit, Glob, Grep, Bash(git:*)
model: opus
---

# Harmonize

Make recently changed code match the patterns, conventions, and style of the surrounding codebase. Changed code should look like it was written by the same team that wrote the rest.

---

## Step 1: Identify changed code

Run these git commands to find changed files:

1. `git diff --name-only` (unstaged changes)
2. `git diff --cached --name-only` (staged changes)
3. If both are empty, fall back to `git diff HEAD~1 --name-only` (last commit)

If not in a git repo or no changes found, report clearly and stop.

Read each changed file in full. Run the corresponding `git diff` to see which sections are new or modified.

## Step 2: Discover surrounding patterns

For each changed file, read 3-5 sibling files in the same directory (prefer shorter, representative files of the same type). Also read files the changed file imports.

Extract established conventions for:

- **Naming** — casing, prefixes, suffixes, abbreviation style
- **Function structure** — ordering, grouping, length
- **Error handling** — early returns, try/catch, Result types
- **Control flow** — early returns vs nested conditionals
- **Import ordering** — stdlib vs third-party vs local, alphabetical vs grouped
- **Comments/docs** — style, frequency, placement
- **Type annotations** — presence, style, specificity
- **Test patterns** — describe/context structure, setup, assertion style (if test files changed)

## Step 3: Check CLAUDE.md

Read any CLAUDE.md files that apply — repo root and parent directories of changed files. Explicit conventions in CLAUDE.md always take precedence over observed patterns.

## Step 4: Identify disharmony

Flag only clear, unambiguous divergences where:

- The surrounding codebase is internally consistent (3+ files agree)
- The changed code clearly deviates from that pattern

If the codebase itself is inconsistent on a pattern, do **nothing** for that category. When in doubt, skip.

## Step 5: Safety checks

Before applying any change, verify ALL of the following:

- **Does not change behavior** — purely cosmetic/structural, no logic changes
- **Does not propagate anti-patterns** — don't harmonize toward bad patterns (swallowed exceptions, god methods, magic numbers)
- **Does not violate SOLID/DRY** — don't introduce duplication or break single-responsibility for consistency
- **Does not reduce type safety** — don't remove or weaken type annotations
- **Does not remove error handling** — don't strip error handling even if surrounding code lacks it
- **CLAUDE.md wins conflicts** — if CLAUDE.md and surrounding code disagree, follow CLAUDE.md

If a change fails any check, skip it.

## Step 6: Apply edits

Use the Edit tool. Make targeted, minimal edits — change only what diverges from the established pattern.

## Step 7: Summarize

After all edits:

- **Files modified** — list each file edited
- **Patterns addressed** — for each file, briefly describe what was harmonized (e.g., "renamed `getUserData` to `get_user_data` to match snake_case convention")
- **Intentionally skipped** — note divergences you left alone and why (e.g., "Mixed import ordering across sibling files — no clear convention")

If no changes were needed: "All changed code already matches surrounding codebase patterns. No harmonization needed."

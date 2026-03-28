#!/bin/bash
set -euo pipefail

# Validation script for the workflow-orchestrator plugin.
# Checks YAML examples, JSON config files, the skill prompt, and cleanup state.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "=== Workflow Orchestrator Validation ==="
echo ""

# ---------------------------------------------------------------------------
# 1. YAML Examples
# ---------------------------------------------------------------------------
YAML_DIR="$REPO_ROOT/.claude/workflows/examples"
echo "[YAML Examples]"

if [ ! -d "$YAML_DIR" ]; then
  fail "examples directory missing: $YAML_DIR"
else
  shopt -s nullglob
  yaml_files=("$YAML_DIR"/*.yaml)
  shopt -u nullglob

  if [ ${#yaml_files[@]} -eq 0 ]; then
    fail "no .yaml files found in $YAML_DIR"
  fi

  for f in "${yaml_files[@]}"; do
    base="$(basename "$f")"

    # Single Python invocation: parse YAML once, run all checks
    py_output=$(python3 - "$f" "$base" <<'PYEOF'
import sys, yaml

path, base = sys.argv[1], sys.argv[2]
VALID_TYPES = {"prompt", "skill", "command", "if", "switch", "loop", "parallel", "workflow", "create-workflow", "fail"}
VALID_RUN_IN = {"main", "agent"}
BRANCH_KEYS = ("then", "else", "steps", "branches")

def visit_nested(step_list, visitor):
    """Walk nested step structures, calling visitor(scope_steps) at each level."""
    visitor(step_list or [])
    for s in (step_list or []):
        if not isinstance(s, dict):
            continue
        for key in BRANCH_KEYS:
            nested = s.get(key)
            if isinstance(nested, list):
                visit_nested(nested, visitor)
            elif isinstance(nested, dict):
                for branch_steps in nested.values():
                    if isinstance(branch_steps, list):
                        visit_nested(branch_steps, visitor)

def p(ok, msg):
    print(("PASS" if ok else "FAIL") + "\t" + msg)

try:
    with open(path) as fh:
        doc = yaml.safe_load(fh)
    p(True, f"{base}: valid YAML")
except Exception:
    p(False, f"{base}: invalid YAML")
    sys.exit(0)  # skip remaining checks for this file

wf = doc.get("workflow") if isinstance(doc, dict) else None
p(
    wf and all(k in wf for k in ("name", "version", "steps")),
    f"{base}: has required fields"
)

steps = wf.get("steps", []) if isinstance(wf, dict) else []
all_have = all(isinstance(s, dict) and "id" in s and "type" in s for s in steps)
if not steps:
    p(False, f"{base}: no steps found")
else:
    p(all_have, f"{base}: all steps have id and type")

# Collect all steps and check types + run_in
all_steps = []
visit_nested(steps, lambda scope: all_steps.extend(s for s in scope if isinstance(s, dict)))

bad_types = [s.get("type") for s in all_steps if s.get("type") not in VALID_TYPES]
p(not bad_types, f"{base}: all step types valid")

bad_run_in = [s["run_in"] for s in all_steps if "run_in" in s and s["run_in"] not in VALID_RUN_IN]
p(not bad_run_in, f"{base}: run_in values valid")

# Check duplicate IDs within each scope
dupes = set()
def find_scope_dupes(scope_steps):
    ids = [s["id"] for s in scope_steps if isinstance(s, dict) and "id" in s]
    seen = set()
    for sid in ids:
        (dupes if sid in seen else seen).add(sid)
visit_nested(steps, find_scope_dupes)
p(not dupes, f"{base}: no duplicate step IDs")
PYEOF
    )
    while IFS=$'\t' read -r status msg; do
      if [ "$status" = "PASS" ]; then
        pass "$msg"
      else
        fail "$msg"
      fi
    done <<< "$py_output"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. JSON Files
# ---------------------------------------------------------------------------
echo "[JSON Files]"

PLUGIN_JSON="$REPO_ROOT/plugins/workflow-orchestrator/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

# plugin.json
if [ ! -f "$PLUGIN_JSON" ]; then
  fail "plugin.json: file not found"
else
  if python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    d = json.load(f)
assert 'name' in d
" "$PLUGIN_JSON" 2>/dev/null; then
    pass "plugin.json: valid JSON with name field"
  else
    fail "plugin.json: invalid JSON or missing name field"
  fi
fi

# marketplace.json — single parse, three checks
if [ ! -f "$MARKETPLACE_JSON" ]; then
  fail "marketplace.json: file not found"
else
  mp_output=$(python3 -c "
import sys, json
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print('PASS\tmarketplace.json: valid JSON')
except Exception:
    print('FAIL\tmarketplace.json: invalid JSON')
    sys.exit(0)
names = [p['name'] for p in d.get('plugins', [])]
print(('PASS' if 'workflow-orchestrator' in names else 'FAIL') + '\tmarketplace.json: contains workflow-orchestrator')
print(('PASS' if 'custom-workflow' not in names else 'FAIL') + '\tmarketplace.json: does not contain custom-workflow')
" "$MARKETPLACE_JSON" 2>/dev/null || echo "FAIL	marketplace.json: python error")
  while IFS=$'\t' read -r status msg; do
    if [ "$status" = "PASS" ]; then
      pass "$msg"
    else
      fail "$msg"
    fi
  done <<< "$mp_output"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Skill Prompt
# ---------------------------------------------------------------------------
SKILL_MD="$REPO_ROOT/plugins/workflow-orchestrator/commands/workflow-orchestrator.md"
echo "[Skill Prompt]"

if [ ! -f "$SKILL_MD" ]; then
  fail "workflow-orchestrator.md: file not found"
else
  pass "workflow-orchestrator.md: exists"

  # Frontmatter check
  if python3 -c "
import sys
text = open(sys.argv[1]).read()
assert text.startswith('---')
parts = text.split('---', 2)
assert len(parts) >= 3
fm = parts[1]
assert 'description' in fm.lower()
assert 'model' in fm.lower()
" "$SKILL_MD" 2>/dev/null; then
    pass "workflow-orchestrator.md: has frontmatter with description and model"
  else
    fail "workflow-orchestrator.md: missing or invalid frontmatter"
  fi

  # Line count
  line_count=$(wc -l < "$SKILL_MD" | tr -d ' ')
  if [ "$line_count" -gt 200 ]; then
    pass "workflow-orchestrator.md: >200 lines ($line_count lines)"
  else
    fail "workflow-orchestrator.md: only $line_count lines (need >200)"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Cleanup
# ---------------------------------------------------------------------------
echo "[Cleanup]"

if [ -d "$REPO_ROOT/plugins/custom-workflow" ]; then
  fail "plugins/custom-workflow/ still exists"
else
  pass "plugins/custom-workflow/ does not exist"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo "=== Results: ${PASS}/${TOTAL} passed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

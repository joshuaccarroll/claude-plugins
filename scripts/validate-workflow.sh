#!/bin/bash
set -euo pipefail

# Validation script for the workflow-orchestrator plugin.
# Checks YAML examples, JSON config files, the skill prompt, and cleanup state.
# Uses Ruby for YAML parsing (built-in on macOS) and Python for JSON.

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

    # Single Ruby invocation: parse YAML once, run all checks
    rb_output=$(ruby - "$f" "$base" <<'RUBYEOF'
require 'yaml'
require 'set'
require 'date'

path, base = ARGV[0], ARGV[1]
VALID_TYPES = %w[prompt skill command if switch loop parallel workflow create-workflow fail].to_set
VALID_RUN_IN = %w[main agent].to_set
BRANCH_KEYS = %w[then else steps branches]

def visit_nested(step_list, &visitor)
  return unless step_list.is_a?(Array)
  visitor.call(step_list)
  step_list.each do |s|
    next unless s.is_a?(Hash)
    # Recurse into nested step lists
    %w[then else steps].each do |key|
      nested = s[key]
      visit_nested(nested, &visitor) if nested.is_a?(Array)
    end
    # branches is a list of {steps: [...]} objects — unwrap each
    if s["branches"].is_a?(Array)
      s["branches"].each do |branch|
        visit_nested(branch["steps"], &visitor) if branch.is_a?(Hash) && branch["steps"].is_a?(Array)
      end
    end
    # cases is a map of value -> step list
    if s["cases"].is_a?(Hash)
      s["cases"].each_value do |case_steps|
        visit_nested(case_steps, &visitor) if case_steps.is_a?(Array)
      end
    end
    # default is a step list
    visit_nested(s["default"], &visitor) if s["default"].is_a?(Array)
  end
end

def p(ok, msg)
  puts "#{ok ? 'PASS' : 'FAIL'}\t#{msg}"
end

begin
  doc = YAML.safe_load(File.read(path), permitted_classes: [Date])
  p true, "#{base}: valid YAML"
rescue => e
  p false, "#{base}: invalid YAML"
  exit 0
end

wf = doc.is_a?(Hash) ? doc["workflow"] : nil
p(wf && %w[name version steps].all? { |k| wf.key?(k) }, "#{base}: has required fields")

steps = wf.is_a?(Hash) ? (wf["steps"] || []) : []
if steps.empty?
  p false, "#{base}: no steps found"
else
  all_have = steps.all? { |s| s.is_a?(Hash) && s.key?("id") && s.key?("type") }
  p all_have, "#{base}: all steps have id and type"
end

# Collect all steps and check types + run_in
all_steps = []
visit_nested(steps) { |scope| all_steps.concat(scope.select { |s| s.is_a?(Hash) }) }

bad_types = all_steps.select { |s| !VALID_TYPES.include?(s["type"]) }.map { |s| s["type"] }
p bad_types.empty?, "#{base}: all step types valid"

bad_run_in = all_steps.select { |s| s.key?("run_in") && !VALID_RUN_IN.include?(s["run_in"]) }.map { |s| s["run_in"] }
p bad_run_in.empty?, "#{base}: run_in values valid"

# Check duplicate IDs within each scope
dupes = Set.new
visit_nested(steps) do |scope_steps|
  ids = scope_steps.select { |s| s.is_a?(Hash) && s.key?("id") }.map { |s| s["id"] }
  seen = Set.new
  ids.each { |sid| (seen.include?(sid) ? dupes : seen).add(sid) }
end
p dupes.empty?, "#{base}: no duplicate step IDs"
RUBYEOF
    )
    while IFS=$'\t' read -r status msg; do
      if [ "$status" = "PASS" ]; then
        pass "$msg"
      else
        fail "$msg"
      fi
    done <<< "$rb_output"
  done
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
  if head -1 "$SKILL_MD" | grep -q '^---' && grep -c '^---' "$SKILL_MD" | grep -q '[2-9]'; then
    fm=$(sed -n '2,/^---$/p' "$SKILL_MD")
    if echo "$fm" | grep -qi 'description' && echo "$fm" | grep -qi 'model'; then
      pass "workflow-orchestrator.md: has frontmatter with description and model"
    else
      fail "workflow-orchestrator.md: frontmatter missing description or model"
    fi
  else
    fail "workflow-orchestrator.md: missing frontmatter delimiters"
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

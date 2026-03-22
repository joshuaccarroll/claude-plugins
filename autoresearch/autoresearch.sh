#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTORESEARCH_DIR="${REPO_ROOT}/autoresearch"
FIXTURES_DIR="${AUTORESEARCH_DIR}/fixtures"
ARTIFACTS_DIR="${AUTORESEARCH_DIR}/artifacts/latest"
RESULTS_TSV="${AUTORESEARCH_DIR}/results.tsv"
PROMPT_SRC="${REPO_ROOT}/plugins/review-plan/commands/review-plan.md"
PROMPT_DEST="${HOME}/.claude/commands/review-plan.md"
TEST_DIR="/tmp/autoresearch-test"
FAILED_DIFFS_DIR="/tmp/autoresearch-failed-diffs/"

RUNS_PER_FIXTURE=10
MAX_BUDGET_PER_RUN="3.00"
TIMEOUT_PER_RUN=300
MAX_TRIAL_WALL_CLOCK=$((180 * 60))
MAX_TRIALS=15
RATE_LIMIT_BACKOFF=300
MAX_RATE_LIMIT_RETRIES=3

FIXTURES=(small-change bug-fix new-feature greenfield)

# ── Checkpoint labels ────────────────────────────────────────────────────────

declare -a LABELS_small_change=("storage persistence" "route change trigger" "responsive layout")
declare -a LABELS_bug_fix=("regex pattern fix" "cache miss handling" "raw text sanitization")
declare -a LABELS_new_feature=("abandon mid-wizard" "level-up data model" "wizard UI component")
declare -a LABELS_greenfield=("authentication" "reconnection" "rate limiting" "LLM integration")

# ── Logging helpers ──────────────────────────────────────────────────────────

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { log "WARN: $*" >&2; }
die()  { log "FATAL: $*" >&2; exit 1; }

# ── run_checkpoints ──────────────────────────────────────────────────────────
# Evaluates fixture-specific quality patterns.
# Outputs one line per pattern: PASS|fixture[idx] or FAIL|fixture[idx]

run_checkpoints() {
  local fixture="$1"

  # Fixture-specific patterns (must match existing checkpoint logic)
  local -a patterns
  case "$fixture" in
    small-change)
      patterns=(
        "storage|persist|localStorage|sessionStorage"
        "route|navigation|path|redirect"
        "responsive|mobile|breakpoint|media.query"
      )
      ;;
    bug-fix)
      patterns=(
        "regex|pattern|match|escape"
        "cache|miss|stale|invalidat"
        "sanitiz|escap|raw|XSS|inject"
      )
      ;;
    new-feature)
      patterns=(
        "abandon|cancel|discard|mid.wizard"
        "level|experience|XP|data.model"
        "wizard|step|multi.step|UI.component"
      )
      ;;
    greenfield)
      patterns=(
        "auth|login|session|token"
        "reconnect|disconnect|retry|socket"
        "rate.limit|throttl|backoff|quota"
        "LLM|language.model|AI|GPT|Claude"
      )
      ;;
    *)
      return
      ;;
  esac

  local plan_content=""
  if [[ -f "${TEST_DIR}/plan.md" ]]; then
    plan_content=$(cat "${TEST_DIR}/plan.md")
  fi

  local idx=0
  for pattern in "${patterns[@]}"; do
    if echo "$plan_content" | grep -qiE "$pattern"; then
      echo "PASS|${fixture}[${idx}]"
    else
      echo "FAIL|${fixture}[${idx}]"
    fi
    idx=$((idx + 1))
  done
}

# ── run_single ───────────────────────────────────────────────────────────────
# Runs one invocation of the review-plan skill against a fixture.
# Communicates results via stdout (pipe-separated: status|iterations|detail).

run_single() {
  local fixture="$1"
  local run_number="$2"
  local artifact_prefix="$3"

  # 1. Prepare workspace
  rm -rf "$TEST_DIR" && mkdir -p "$TEST_DIR"
  cp "${FIXTURES_DIR}/${fixture}.md" "${TEST_DIR}/plan.md"
  local pre_hash
  pre_hash=$(md5 -q "${TEST_DIR}/plan.md")

  # 2. Deploy prompt
  mkdir -p "$(dirname "$PROMPT_DEST")"
  cp "$PROMPT_SRC" "$PROMPT_DEST"

  # 3. Invoke Claude
  local raw_output exit_code
  raw_output=$(timeout "$TIMEOUT_PER_RUN" claude -p \
    --output-format json \
    --dangerously-skip-permissions \
    --max-budget-usd "$MAX_BUDGET_PER_RUN" \
    --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Task*" \
    "Use the /review-plan skill to review the plan at ${TEST_DIR}/plan.md" 2>&1) || {
      exit_code=$?
      if [[ $exit_code -eq 124 ]]; then
        echo "stopped_early|0|timeout"
        return 0
      fi
      echo "stopped_early|0|error_${exit_code}"
      return 0
    }

  # 4. Save raw output
  echo "$raw_output" > "${artifact_prefix}_raw.json"

  # 5. Extract RESULT line
  local result_text result_line
  result_text=$(echo "$raw_output" | jq -r '.result // empty' 2>/dev/null || echo "$raw_output")
  result_line=$(echo "$result_text" | grep -oE 'RESULT: status=[a-z_]+ iterations=[0-9]+' | tail -1 || true)

  # 6. Parse fields
  if [[ -z "$result_line" ]]; then
    echo "stopped_early|0|no_result_line"
    return 0
  fi

  local status iterations
  status=$(echo "$result_line" | sed 's/.*status=\([a-z_]*\).*/\1/')
  iterations=$(echo "$result_line" | sed 's/.*iterations=\([0-9]*\).*/\1/')

  # 7. Validate convergence — check for false convergence
  if [[ "$status" == "converged" && "$iterations" -le 1 ]]; then
    local post_hash
    post_hash=$(md5 -q "${TEST_DIR}/plan.md")
    if [[ "$pre_hash" == "$post_hash" ]]; then
      echo "stopped_early|${iterations}|false_convergence"
      return 0
    fi
  fi

  # 8. Run checkpoints and save per-pattern results
  local checkpoint_output
  checkpoint_output=$(run_checkpoints "$fixture")
  echo "$checkpoint_output" > "${artifact_prefix}_checkpoints.txt"

  # 9. Return result (main format unchanged)
  echo "${status}|${iterations}|ok"
}

# ── score_result_file ────────────────────────────────────────────────────────
# Scores a single result file. Returns 0-3 via stdout.
# +1 if status != stopped_early (COMPLETED)
# +1 if status == converged (CONVERGED)
# +1 if quality == 1 (QUALITY — has checkpoint passes)

score_result_file() {
  local result_file="$1"
  local score=0

  if [[ ! -f "$result_file" ]]; then
    echo "0"
    return
  fi

  local content
  content=$(cat "$result_file")
  local status
  status=$(echo "$content" | cut -d'|' -f1)

  # +1 COMPLETED
  if [[ "$status" != "stopped_early" ]]; then
    score=$((score + 1))
  fi

  # +1 CONVERGED
  if [[ "$status" == "converged" ]]; then
    score=$((score + 1))
  fi

  # +1 QUALITY: check associated checkpoints file
  # result file is ${prefix}_result.txt, checkpoints file is ${prefix}_checkpoints.txt
  local checkpoint_file="${result_file%_result.txt}_checkpoints.txt"
  if [[ -f "$checkpoint_file" ]]; then
    local pass_count
    pass_count=$(grep -c '^PASS' "$checkpoint_file" || true)
    local total_count
    total_count=$(grep -c '.' "$checkpoint_file" || true)
    if [[ "$total_count" -gt 0 && "$pass_count" -eq "$total_count" ]]; then
      score=$((score + 1))
    fi
  fi

  echo "$score"
}

# ── run_trial ────────────────────────────────────────────────────────────────
# Runs all fixtures * runs and produces a score.
# Returns via stdout: score|avg_iterations

run_trial() {
  local trial_number="$1"
  local label="$2"

  # 1. Clean artifacts
  rm -rf "$ARTIFACTS_DIR" && mkdir -p "$ARTIFACTS_DIR"

  # Record word count for conciseness guidance
  local prompt_word_count=0
  if [[ -f "$PROMPT_SRC" ]]; then
    prompt_word_count=$(wc -w < "$PROMPT_SRC" | tr -d ' ')
  fi
  echo "$prompt_word_count" > "${ARTIFACTS_DIR}/word_count.txt"

  # 2. Record start time
  local trial_start
  trial_start=$(date +%s)

  local total_score=0 total_iterations=0 total_runs=0

  # 3. Loop over fixtures and runs (sequential)
  for fixture in "${FIXTURES[@]}"; do
    for run in $(seq 1 "$RUNS_PER_FIXTURE"); do
      # Check wall-clock limit
      local elapsed=$(( $(date +%s) - trial_start ))
      if [[ $elapsed -ge $MAX_TRIAL_WALL_CLOCK ]]; then
        warn "Wall-clock limit reached after ${elapsed}s"
        break 2
      fi

      local artifact_prefix="${ARTIFACTS_DIR}/${fixture}_run${run}"
      local result=""
      local retries=0

      # Rate-limit retry loop
      while [[ $retries -le $MAX_RATE_LIMIT_RETRIES ]]; do
        result=$(run_single "$fixture" "$run" "$artifact_prefix")

        if echo "$result" | grep -qiE 'rate_limit|429'; then
          retries=$((retries + 1))
          if [[ $retries -gt $MAX_RATE_LIMIT_RETRIES ]]; then
            warn "Max rate-limit retries exceeded for ${fixture} run ${run}"
            break
          fi
          warn "Rate limited on ${fixture} run ${run}, backing off ${RATE_LIMIT_BACKOFF}s (retry ${retries}/${MAX_RATE_LIMIT_RETRIES})"
          sleep "$RATE_LIMIT_BACKOFF"
        else
          break
        fi
      done

      # Save result to file for score_result_file()
      echo "$result" > "${artifact_prefix}_result.txt"

      # Parse pipe-separated result
      local status detail iter
      status=$(echo "$result" | cut -d'|' -f1)
      iter=$(echo "$result" | cut -d'|' -f2)
      detail=$(echo "$result" | cut -d'|' -f3)

      total_runs=$((total_runs + 1))

      # Score using score_result_file()
      local run_score
      run_score=$(score_result_file "${artifact_prefix}_result.txt")
      total_score=$((total_score + run_score))
      total_iterations=$((total_iterations + iter))

      # Log per-run result
      local run_log="${fixture} run ${run}: status=${status} iterations=${iter} detail=${detail} score=${run_score}"
      log "$run_log"
      echo "$run_log" >> "${ARTIFACTS_DIR}/summary.txt"
    done
  done

  # 4. Aggregate checkpoint data
  {
    echo "Per-checkpoint pass rates (${RUNS_PER_FIXTURE} runs each):"
    for fixture in "${FIXTURES[@]}"; do
      local label_var="LABELS_${fixture//-/_}"
      local -a labels
      eval "labels=(\"\${${label_var}[@]}\")"

      local idx=0
      for lbl in "${labels[@]}"; do
        local key="${fixture}[${idx}]"
        local pass_count=0 total_count=0
        for f in "${ARTIFACTS_DIR}/${fixture}_run"*"_checkpoints.txt"; do
          [[ -f "$f" ]] || continue
          total_count=$((total_count + 1))
          if grep -q "^PASS|${key}$" "$f" 2>/dev/null; then
            pass_count=$((pass_count + 1))
          fi
        done
        if [[ $total_count -gt 0 ]]; then
          echo "  ${key} (${lbl}): ${pass_count}/${total_count}"
        fi
        idx=$((idx + 1))
      done
    done
  } > "${ARTIFACTS_DIR}/checkpoint_detail.txt"

  # 5. Compute stats
  local score=$total_score

  local convergence_rate="0"
  local converged=0 completed=0
  # Recompute completed/converged for TSV notes
  for f in "${ARTIFACTS_DIR}/"*"_result.txt"; do
    [[ -f "$f" ]] || continue
    local s
    s=$(cut -d'|' -f1 < "$f")
    if [[ "$s" != "stopped_early" ]]; then
      completed=$((completed + 1))
    fi
    if [[ "$s" == "converged" ]]; then
      converged=$((converged + 1))
    fi
  done

  if [[ $total_runs -gt 0 ]]; then
    convergence_rate=$(awk "BEGIN { printf \"%.2f\", ${converged}/${total_runs} }")
  fi

  local avg_iterations="0"
  if [[ $total_runs -gt 0 ]]; then
    avg_iterations=$(awk "BEGIN { printf \"%.1f\", ${total_iterations}/${total_runs} }")
  fi

  local duration=$(( $(date +%s) - trial_start ))

  # 6. Append to results.tsv
  if [[ ! -f "$RESULTS_TSV" ]]; then
    printf 'trial\ttimestamp\tlabel\tscore\tconvergence_rate\tavg_iterations\tduration_sec\tnotes\n' > "$RESULTS_TSV"
  fi
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$trial_number" "$timestamp" "$label" "$score" "$convergence_rate" "$avg_iterations" "$duration" \
    "completed=${completed} converged=${converged} runs=${total_runs} words=${prompt_word_count}" >> "$RESULTS_TSV"

  log "Trial ${trial_number} complete: score=${score}/120 convergence=${convergence_rate} avg_iter=${avg_iterations} duration=${duration}s"

  # 7. Return score and avg_iterations
  echo "${score}|${avg_iterations}"
}

# ── invoke_mutator ───────────────────────────────────────────────────────────
# Asks a mutator agent to make one targeted edit to the prompt.

invoke_mutator() {
  local trial_number="$1"
  local current_score="$2"
  local best_score="$3"
  local best_commit="${4:-}"

  local trial_summary=""
  if [[ -f "${ARTIFACTS_DIR}/summary.txt" ]]; then
    trial_summary=$(cat "${ARTIFACTS_DIR}/summary.txt")
  fi

  local current_prompt=""
  if [[ -f "$PROMPT_SRC" ]]; then
    current_prompt=$(cat "$PROMPT_SRC")
  fi

  # Read checkpoint detail
  local checkpoint_detail=""
  if [[ -f "${ARTIFACTS_DIR}/checkpoint_detail.txt" ]]; then
    checkpoint_detail=$(cat "${ARTIFACTS_DIR}/checkpoint_detail.txt")
  fi

  # Read word count
  local word_count="0"
  if [[ -f "${ARTIFACTS_DIR}/word_count.txt" ]]; then
    word_count=$(cat "${ARTIFACTS_DIR}/word_count.txt")
  fi

  # Read up to 5 most recent failed diffs
  local failed_diffs_content=""
  if [[ -d "$FAILED_DIFFS_DIR" ]]; then
    local diff_count=0
    for f in $(ls -t "$FAILED_DIFFS_DIR"/*.diff 2>/dev/null | head -5); do
      diff_count=$((diff_count + 1))
      failed_diffs_content="${failed_diffs_content}
--- Failed diff #${diff_count} ($(basename "$f")) ---
$(cat "$f")
"
    done
  fi

  local mutator_prompt
  mutator_prompt="You are optimizing a Claude Code skill prompt for the /review-plan command.

CURRENT SCORE: ${current_score}/120
BEST SCORE:    ${best_score}/120

The score is: (completed: +1) + (converged: +1) + (quality checkpoints all pass: +1) per run.
Total possible: 120 (40 runs x 3 criteria each).

LATEST TRIAL SUMMARY:
${trial_summary}
"

  if [[ -n "$checkpoint_detail" ]]; then
    mutator_prompt="${mutator_prompt}
CHECKPOINT DETAIL:
${checkpoint_detail}
"
  fi

  mutator_prompt="${mutator_prompt}
CURRENT PROMPT (file: ${PROMPT_SRC}):
${current_prompt}
"

  if [[ -n "$failed_diffs_content" ]]; then
    mutator_prompt="${mutator_prompt}
PREVIOUS FAILED MUTATION DIFFS:
${failed_diffs_content}
"
  fi

  mutator_prompt="${mutator_prompt}
KEY INSIGHT: Shorter prompts consistently outperform longer ones. The model already
knows how to review a plan — over-specifying narrows attention and wastes budget.
Current prompt is ${word_count} words. Prefer removing or simplifying over adding.

YOUR TASK:
Make ONE targeted edit to the prompt file at ${PROMPT_SRC} to improve the score.

Focus areas:
- Clearer convergence signals so the agent knows when the plan is good enough
- Preventing premature stopping (the agent should not give up early)
- Reducing unnecessary iterations (the agent should not loop more than needed)

Constraints:
- Do NOT change the RESULT: output format (RESULT: status=<status> iterations=<N>)
- Do NOT remove the sub-agent RESULT: prohibition (sub-agents must not emit RESULT: lines)
- Make ONE change, not a full rewrite
- The file must stay at least 2 lines long
- Edit the file directly at: ${PROMPT_SRC}
"

  log "Invoking mutator for trial ${trial_number}..."

  local max_diversity_retries=2
  local attempt=0

  while [[ $attempt -le $max_diversity_retries ]]; do
    timeout 120 claude -p \
      --dangerously-skip-permissions \
      --max-budget-usd 1.00 \
      --allowedTools "Read,Edit" \
      "$mutator_prompt" > /dev/null 2>&1 || {
        warn "Mutator invocation failed (exit $?)"
      }

    # Verify the RESULT: instruction survived
    if ! grep -q 'RESULT:' "$PROMPT_SRC"; then
      warn "Mutator removed RESULT: instruction — restoring from git"
      restore_prompt "$best_commit"
    fi

    # Check for duplicate diff (diversity enforcement)
    if [[ -n "$best_commit" && -d "$FAILED_DIFFS_DIR" ]]; then
      git -C "$REPO_ROOT" diff "${best_commit}" -- "$PROMPT_SRC" > /tmp/autoresearch-candidate.diff 2>/dev/null || true
      local is_duplicate=false
      for f in "$FAILED_DIFFS_DIR"/*.diff; do
        [[ -f "$f" ]] || continue
        if diff -q /tmp/autoresearch-candidate.diff "$f" > /dev/null 2>&1; then
          is_duplicate=true
          break
        fi
      done

      if [[ "$is_duplicate" == "true" ]]; then
        attempt=$((attempt + 1))
        if [[ $attempt -gt $max_diversity_retries ]]; then
          warn "All ${max_diversity_retries} diversity retries produced duplicate diffs — skipping mutation"
          restore_prompt "$best_commit"
          return 1
        fi
        warn "Duplicate diff detected — retrying with stronger diversity instruction (attempt ${attempt})"
        restore_prompt "$best_commit"

        # Count failed diffs
        local num_failed=0
        num_failed=$(ls "$FAILED_DIFFS_DIR"/*.diff 2>/dev/null | wc -l | tr -d ' ')

        mutator_prompt="${mutator_prompt}

IMPORTANT: You already tried this exact change and it did not improve the score.
Previous failed attempts: ${num_failed} (diffs listed above).
You MUST try something fundamentally different. Consider:
- Changing the tone or framing rather than adding structure
- Removing words rather than adding them (shorter prompts score better)
- Adding context about what makes a good plan review rather than process instructions
"
        continue
      fi
    fi

    # No duplicate — success
    break
  done

  return 0
}

# ── restore_prompt ────────────────────────────────────────────────────────────
# Restores PROMPT_SRC from a specific commit, or HEAD if no commit given.

restore_prompt() {
  local commit="${1:-}"
  if [[ -n "$commit" ]]; then
    git -C "$REPO_ROOT" checkout "$commit" -- "$PROMPT_SRC"
  else
    git -C "$REPO_ROOT" checkout -- "$PROMPT_SRC"
  fi
}

# ── run_quick_check ──────────────────────────────────────────────────────────
# Runs one quick run per fixture (4 total, in parallel) and returns total score.
# Max score: 12 (4 fixtures × 3 criteria)

run_quick_check() {
  mkdir -p "${ARTIFACTS_DIR}/quick"

  local pids=()
  for fixture in "${FIXTURES[@]}"; do
    local artifact_prefix="${ARTIFACTS_DIR}/quick/${fixture}"
    (
      result=$(run_single "$fixture" 0 "$artifact_prefix")
      echo "$result" > "${artifact_prefix}_result.txt"
    ) &
    pids+=($!)
  done

  # Wait for all
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Sum scores
  local quick_score=0
  for fixture in "${FIXTURES[@]}"; do
    local result_file="${ARTIFACTS_DIR}/quick/${fixture}_result.txt"
    local s
    s=$(score_result_file "$result_file")
    quick_score=$((quick_score + s))
  done

  echo "$quick_score"
}

# ── run_loop ─────────────────────────────────────────────────────────────────
# Main optimization loop: trial -> evaluate -> mutate -> repeat.

run_loop() {
  local best_score=0
  local best_avg_iters=999
  local best_commit=""
  local consecutive_perfect=0
  local consecutive_no_improve=0

  # Ensure failed diffs directory exists (preserved across runs)
  mkdir -p "$FAILED_DIFFS_DIR"

  # Create working branch
  git -C "$REPO_ROOT" checkout -b "autoresearch/optimize-review-plan" 2>/dev/null || \
    git -C "$REPO_ROOT" checkout "autoresearch/optimize-review-plan" 2>/dev/null || true

  log "Starting optimization loop (max ${MAX_TRIALS} trials)"

  for trial in $(seq 1 "$MAX_TRIALS"); do
    log "=== Trial ${trial}/${MAX_TRIALS} ==="

    # a. Run trial
    local trial_result
    trial_result=$(run_trial "$trial" "trial_${trial}")
    local score avg_iters
    score=$(echo "$trial_result" | cut -d'|' -f1)
    avg_iters=$(echo "$trial_result" | cut -d'|' -f2)

    # b. Compare to best
    local keep=false
    if [[ "$score" -gt "$best_score" ]]; then
      keep=true
      log "New best score: ${score} (was ${best_score})"
    elif [[ "$score" -eq "$best_score" ]]; then
      local is_better
      is_better=$(awk "BEGIN { print (${avg_iters} < ${best_avg_iters}) ? 1 : 0 }")
      if [[ "$is_better" -eq 1 ]]; then
        keep=true
        log "Same score but better avg iterations: ${avg_iters} (was ${best_avg_iters})"
      fi
    fi

    if [[ "$keep" == "true" ]]; then
      best_score=$score
      best_avg_iters=$avg_iters
      git -C "$REPO_ROOT" add "$PROMPT_SRC"
      git -C "$REPO_ROOT" commit -m "autoresearch: trial ${trial} — score ${score}" --allow-empty || true
      best_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)
      consecutive_no_improve=0
      # Clean up failed diffs on improvement
      rm -f "$FAILED_DIFFS_DIR"/*.diff 2>/dev/null || true
    else
      log "No improvement (score=${score}, best=${best_score}) — reverting"
      # Save failed diff (Step 1 fix: diff against best_commit, not working tree)
      git -C "$REPO_ROOT" diff "${best_commit}" HEAD -- "$PROMPT_SRC" > "$FAILED_DIFFS_DIR/failed_$(date +%s).diff" 2>/dev/null || true
      restore_prompt "$best_commit"
      consecutive_no_improve=$((consecutive_no_improve + 1))
    fi

    # c. Track consecutive perfect
    if [[ "$score" -eq 120 ]]; then
      consecutive_perfect=$((consecutive_perfect + 1))
    else
      consecutive_perfect=0
    fi

    # d. Stop conditions
    if [[ $consecutive_perfect -ge 2 ]]; then
      log "Two consecutive perfect scores — stopping"
      break
    fi
    if [[ $consecutive_no_improve -ge 3 ]]; then
      log "Three consecutive trials with no improvement — stopping"
      break
    fi

    # e. Invoke mutator (unless last trial or stopping)
    if [[ $trial -lt $MAX_TRIALS ]]; then
      invoke_mutator "$trial" "$score" "$best_score" "$best_commit"

      # f. Post-mutation sanity check
      local line_count
      line_count=$(wc -l < "$PROMPT_SRC" | tr -d ' ')
      if [[ ! -s "$PROMPT_SRC" || "$line_count" -lt 2 ]]; then
        warn "Post-mutation file is empty or too short (${line_count} lines) — restoring"
        restore_prompt "$best_commit"

        # Retry mutation once
        invoke_mutator "$trial" "$score" "$best_score" "$best_commit"
        line_count=$(wc -l < "$PROMPT_SRC" | tr -d ' ')
        if [[ ! -s "$PROMPT_SRC" || "$line_count" -lt 2 ]]; then
          warn "Retry mutation also failed — keeping restored version"
          restore_prompt "$best_commit"
        fi
      fi

      # g. Quick-reject before committing mutation
      local quick_score
      quick_score=$(run_quick_check)
      local quick_threshold=$(( best_score * 6 / 100 ))
      if [[ "$quick_score" -lt "$quick_threshold" ]]; then
        warn "Quick-reject: score ${quick_score} < threshold ${quick_threshold} — rejecting mutation"
        # Save rejected diff
        git -C "$REPO_ROOT" diff "${best_commit}" -- "$PROMPT_SRC" > "$FAILED_DIFFS_DIR/failed_$(date +%s).diff" 2>/dev/null || true
        restore_prompt "$best_commit"

        # Retry mutation once with diversity enforcement
        invoke_mutator "$trial" "$score" "$best_score" "$best_commit"
        line_count=$(wc -l < "$PROMPT_SRC" | tr -d ' ')
        if [[ ! -s "$PROMPT_SRC" || "$line_count" -lt 2 ]]; then
          restore_prompt "$best_commit"
        else
          quick_score=$(run_quick_check)
          if [[ "$quick_score" -lt "$quick_threshold" ]]; then
            warn "Quick-reject retry also failed (${quick_score} < ${quick_threshold}) — skipping mutation"
            git -C "$REPO_ROOT" diff "${best_commit}" -- "$PROMPT_SRC" > "$FAILED_DIFFS_DIR/failed_$(date +%s).diff" 2>/dev/null || true
            restore_prompt "$best_commit"
            continue
          fi
        fi
      fi

      # h. Commit mutation (only if we get here — not quick-rejected)
      git -C "$REPO_ROOT" add "$PROMPT_SRC"
      git -C "$REPO_ROOT" commit -m "autoresearch: trial ${trial} mutation" --allow-empty || true
    fi
  done

  # Final report
  log "========================================"
  log "Optimization complete"
  log "Best score:          ${best_score}/120"
  log "Best avg iterations: ${best_avg_iters}"
  log "Best commit:         ${best_commit:-none}"
  log "========================================"
}

# ── Main dispatch ────────────────────────────────────────────────────────────

main() {
  case "${1:-}" in
    single)
      [[ -n "${2:-}" && -n "${3:-}" ]] || die "Usage: $0 single <fixture> <run>"
      run_single "$2" "$3" "/tmp/autoresearch-single"
      ;;
    trial)
      run_trial "${2:-1}" "${3:-manual}"
      ;;
    loop)
      run_loop
      ;;
    *)
      echo "Usage: $0 {single|trial|loop} [args...]"
      exit 1
      ;;
  esac
}

main "$@"

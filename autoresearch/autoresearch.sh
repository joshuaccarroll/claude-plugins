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
FAILED_DIFF="/tmp/autoresearch-last-failed.diff"

RUNS_PER_FIXTURE=10
MAX_BUDGET_PER_RUN="2.00"
TIMEOUT_PER_RUN=300
MAX_TRIAL_WALL_CLOCK=$((180 * 60))
MAX_TRIALS=15
RATE_LIMIT_BACKOFF=300
MAX_RATE_LIMIT_RETRIES=3

FIXTURES=(small-change bug-fix new-feature greenfield)

# ── Logging helpers ──────────────────────────────────────────────────────────

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { log "WARN: $*" >&2; }
die()  { log "FATAL: $*" >&2; exit 1; }

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

  # 8. Return result
  echo "${status}|${iterations}|ok"
}

# ── run_trial ────────────────────────────────────────────────────────────────
# Runs all fixtures * runs and produces a score.
# Returns via stdout: score|avg_iterations

run_trial() {
  local trial_number="$1"
  local label="$2"

  # 1. Clean artifacts
  rm -rf "$ARTIFACTS_DIR" && mkdir -p "$ARTIFACTS_DIR"

  # 2. Record start time
  local trial_start
  trial_start=$(date +%s)

  local completed=0 converged=0 total_iterations=0 total_runs=0

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

      # Parse pipe-separated result
      local status detail iter
      status=$(echo "$result" | cut -d'|' -f1)
      iter=$(echo "$result" | cut -d'|' -f2)
      detail=$(echo "$result" | cut -d'|' -f3)

      total_runs=$((total_runs + 1))

      # Score: criterion 1 = completed, criterion 2 = converged
      if [[ "$status" != "stopped_early" ]]; then
        completed=$((completed + 1))
      fi
      if [[ "$status" == "converged" ]]; then
        converged=$((converged + 1))
      fi
      total_iterations=$((total_iterations + iter))

      # Log per-run result
      local run_log="${fixture} run ${run}: status=${status} iterations=${iter} detail=${detail}"
      log "$run_log"
      echo "$run_log" >> "${ARTIFACTS_DIR}/summary.txt"
    done
  done

  # 4. Compute score
  local score=$((completed + converged))

  # 5. Compute stats
  local convergence_rate="0"
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
    "completed=${completed} converged=${converged} runs=${total_runs}" >> "$RESULTS_TSV"

  log "Trial ${trial_number} complete: score=${score}/80 convergence=${convergence_rate} avg_iter=${avg_iterations} duration=${duration}s"

  # 7. Return score and avg_iterations
  echo "${score}|${avg_iterations}"
}

# ── invoke_mutator ───────────────────────────────────────────────────────────
# Asks a mutator agent to make one targeted edit to the prompt.

invoke_mutator() {
  local trial_number="$1"
  local current_score="$2"
  local best_score="$3"

  local trial_summary=""
  if [[ -f "${ARTIFACTS_DIR}/summary.txt" ]]; then
    trial_summary=$(cat "${ARTIFACTS_DIR}/summary.txt")
  fi

  local current_prompt=""
  if [[ -f "$PROMPT_SRC" ]]; then
    current_prompt=$(cat "$PROMPT_SRC")
  fi

  local failed_diff_content=""
  if [[ -f "$FAILED_DIFF" ]]; then
    failed_diff_content=$(cat "$FAILED_DIFF")
  fi

  local mutator_prompt
  mutator_prompt="You are optimizing a Claude Code skill prompt for the /review-plan command.

CURRENT SCORE: ${current_score}/80
BEST SCORE:    ${best_score}/80

The score is: (number of runs that completed without stopping early) + (number of runs that converged).
Total possible: 80 (40 runs x 2 criteria each).

LATEST TRIAL SUMMARY:
${trial_summary}

CURRENT PROMPT (file: ${PROMPT_SRC}):
${current_prompt}
"

  if [[ -n "$failed_diff_content" ]]; then
    mutator_prompt="${mutator_prompt}
LAST FAILED MUTATION DIFF:
${failed_diff_content}
"
  fi

  mutator_prompt="${mutator_prompt}
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
- The file must stay at least 10 lines long
- Edit the file directly at: ${PROMPT_SRC}
"

  log "Invoking mutator for trial ${trial_number}..."
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
    git -C "$REPO_ROOT" checkout -- "$PROMPT_SRC"
  fi
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

# ── run_loop ─────────────────────────────────────────────────────────────────
# Main optimization loop: trial -> evaluate -> mutate -> repeat.

run_loop() {
  local best_score=0
  local best_avg_iters=999
  local best_commit=""
  local consecutive_perfect=0
  local consecutive_no_improve=0

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
    else
      log "No improvement (score=${score}, best=${best_score}) — reverting"
      # Save failed diff
      git -C "$REPO_ROOT" diff "$PROMPT_SRC" > "$FAILED_DIFF" 2>/dev/null || true
      git -C "$REPO_ROOT" checkout -- "$PROMPT_SRC"
      consecutive_no_improve=$((consecutive_no_improve + 1))
    fi

    # c. Track consecutive perfect
    if [[ "$score" -eq 80 ]]; then
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
      invoke_mutator "$trial" "$score" "$best_score"

      # f. Post-mutation sanity check
      local line_count
      line_count=$(wc -l < "$PROMPT_SRC" | tr -d ' ')
      if [[ ! -s "$PROMPT_SRC" || "$line_count" -lt 10 ]]; then
        warn "Post-mutation file is empty or too short (${line_count} lines) — restoring"
        restore_prompt "$best_commit"

        # Retry mutation once
        invoke_mutator "$trial" "$score" "$best_score"
        line_count=$(wc -l < "$PROMPT_SRC" | tr -d ' ')
        if [[ ! -s "$PROMPT_SRC" || "$line_count" -lt 10 ]]; then
          warn "Retry mutation also failed — keeping restored version"
          restore_prompt "$best_commit"
        fi
      fi

      # g. Commit mutation
      git -C "$REPO_ROOT" add "$PROMPT_SRC"
      git -C "$REPO_ROOT" commit -m "autoresearch: trial ${trial} mutation" --allow-empty || true
    fi
  done

  # Final report
  log "========================================"
  log "Optimization complete"
  log "Best score:          ${best_score}/80"
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

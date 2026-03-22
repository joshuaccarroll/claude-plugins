#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
AUTORESEARCH_DIR="${REPO_ROOT}/autoresearch"
FIXTURES_DIR="${AUTORESEARCH_DIR}/fixtures"
ARTIFACTS_DIR="${AUTORESEARCH_DIR}/artifacts/latest"
RESULTS_TSV="${AUTORESEARCH_DIR}/results.tsv"
PROMPT_SRC="${REPO_ROOT}/plugins/review-plan/commands/review-plan.md"
PROMPT_DEST="${HOME}/.claude/commands/review-plan.md"
FAILED_DIFF="/tmp/autoresearch-last-failed.diff"

RUNS_PER_FIXTURE="${RUNS_PER_FIXTURE:-10}"
PARALLEL_JOBS="${PARALLEL_JOBS:-8}"
MAX_BUDGET_PER_RUN="2.00"
TIMEOUT_PER_RUN=600
MAX_TRIAL_WALL_CLOCK=$((300 * 60))
MAX_TRIALS=15
RATE_LIMIT_BACKOFF=300
MAX_RATE_LIMIT_RETRIES=3

FIXTURES=(small-change bug-fix new-feature greenfield)

# ── Logging helpers ──────────────────────────────────────────────────────────

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { log "WARN: $*" >&2; }
die()  { log "FATAL: $*" >&2; exit 1; }

# ── Portable timeout ────────────────────────────────────────────────────────
# macOS lacks `timeout` by default; use perl as a fallback.

if ! command -v timeout &>/dev/null; then
  timeout() {
    local duration="$1"; shift
    perl -e '
      alarm shift @ARGV;
      $SIG{ALRM} = sub { kill 9, $pid; exit 124 };
      $pid = fork // die "fork: $!";
      if ($pid == 0) { exec @ARGV; die "exec: $!" }
      waitpid $pid, 0;
      exit ($? >> 8);
    ' "$duration" "$@"
  }
fi

# ── validate_prompt ──────────────────────────────────────────────────────────
# Checks 3 invariants against the prompt file. Returns 0 (pass) or 1 (fail).
# If any invariant fails, the trial should score 0.

validate_prompt() {
  local prompt_file="$1"

  # Invariant 1: Prompt instructs creating a plan file if one doesn't exist
  if ! grep -iEq 'write.*plan.*file|write.*to.*\.md|write it to|create.*file|save.*plan.*file' "$prompt_file"; then
    warn "INVARIANT FAIL: Prompt does not instruct creating a plan file"
    return 1
  fi

  # Invariant 2: Prompt does NOT claim the plan was "already reviewed"
  if grep -iEq 'already been reviewed|already.*reviewed.*improved|prior round|previous round' "$prompt_file"; then
    warn "INVARIANT FAIL: Prompt introduces false assumptions about prior review"
    return 1
  fi

  # Invariant 3: Prompt does NOT bias toward convergence as expected default
  if grep -iEq 'most plans.*ready|expected response.*CONVERGED|CONVERGED.*expected response|convergence.*expected' "$prompt_file"; then
    warn "INVARIANT FAIL: Prompt lowers quality bar by redefining success"
    return 1
  fi

  return 0
}

# ── run_checkpoints ─────────────────────────────────────────────────────────
# Evaluates fixture-specific quality checkpoints against a reviewed plan.
# A checkpoint passes only if the pattern is NOT in the raw fixture but IS
# in the reviewed plan (prevents false positives from pre-existing text).
# Prints "passed/total" to stdout.

run_checkpoints() {
  local fixture="$1"
  local reviewed_file="$2"
  local raw_file="${FIXTURES_DIR}/${fixture}.md"
  local passed=0 total=0

  local patterns=()
  case "$fixture" in
    small-change)
      patterns=(
        'localStorage|zustand.*persist|existing.*persist|current.*storage|investigate.*persist|how.*currently'
        'route.*change|on.*navigate|component.*mount|click.*card|trigger.*when.*mark|useEffect|fire.*when|fires when'
        'responsive|breakpoint|overflow.*scroll|small.screen|narrow|@media|flex.*wrap|media.*query'
      ) ;;
    bug-fix)
      patterns=(
        'RegExp|new RegExp|replace\(\/|\.match\(\/|regex.*pattern|\\[<>*_~]'
        'cache.*miss|not.*found.*user|lookup.*fail|resolve.*fail|fallback.*name|unknown.*user|stale.*cache'
        'strip.*raw|pass.*through|best.effort|fallback.*text|leave.*as.is|escape.*markup|sanitize'
      ) ;;
    new-feature)
      patterns=(
        'abandon|cancel.*level|partial.*save|discard|unsaved.*change|close.*wizard|back.*button|undo.*level'
        'history.*\[|levelUp.*{|LevelUpRecord|changelog|progression.*array|record.*{.*level'
        'dialog|modal.*component|fullscreen.*modal|route.*/level|drawer|side.*panel|bottom.*sheet|overlay.*component'
      ) ;;
    greenfield)
      patterns=(
        'authenticat|session.*id|token|cookie|identity|login|uuid|anonymous.*id|player.*identif|sign.?in|oauth'
        'reconnect|restore.*state|persist.*state|redis|recover.*session|heartbeat|rejoin'
        'rate.?limit|throttl|cooldown|debounce|abuse|spam|quota|max.*request'
        'system.*prompt|example.*card|few.?shot|temperature|you are|generate.*json|format.*output|sample.*response'
      ) ;;
  esac

  for pattern in "${patterns[@]}"; do
    total=$((total + 1))
    if ! grep -iEq "$pattern" "$raw_file" && grep -iEq "$pattern" "$reviewed_file"; then
      passed=$((passed + 1))
    fi
  done

  echo "${passed}/${total}"
}

# ── run_single ───────────────────────────────────────────────────────────────
# Runs one invocation of the review-plan skill against a fixture.
# Writes result to ${artifact_prefix}_result.txt.
# Format: status|iterations|quality|checkpoints_passed|checkpoints_total|detail
# Uses an isolated temp dir per run for parallel safety.

run_single() {
  local fixture="$1"
  local run_number="$2"
  local artifact_prefix="$3"
  local result_file="${artifact_prefix}_result.txt"

  # 1. Prepare isolated workspace
  local work_dir="/tmp/autoresearch-${fixture}-run${run_number}"
  rm -rf "$work_dir" && mkdir -p "$work_dir"
  cp "${FIXTURES_DIR}/${fixture}.md" "${work_dir}/plan.md"
  local pre_hash
  pre_hash=$(md5 -q "${work_dir}/plan.md")

  # 2. Invoke Claude (prompt deployed once by run_trial before launching)
  local raw_output exit_code
  raw_output=$(echo "Use the /review-plan skill to review the plan at ${work_dir}/plan.md" | \
    timeout "$TIMEOUT_PER_RUN" claude -p \
    --output-format json \
    --dangerously-skip-permissions \
    --max-budget-usd "$MAX_BUDGET_PER_RUN" \
    --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Task*" \
    2>&1) || {
      exit_code=$?
      rm -rf "$work_dir"
      if [[ $exit_code -eq 124 ]]; then
        echo "stopped_early|0|0|0|0|timeout" > "$result_file"
        return 0
      fi
      echo "stopped_early|0|0|0|0|error_${exit_code}" > "$result_file"
      return 0
    }

  # 3. Save raw output
  echo "$raw_output" > "${artifact_prefix}_raw.json"

  # 4. Extract RESULT line
  local result_text result_line
  result_text=$(echo "$raw_output" | jq -r '.result // empty' 2>/dev/null || echo "$raw_output")
  result_line=$(echo "$result_text" | grep -oE 'RESULT: status=[a-z_]+ iterations=[0-9]+' | tail -1 || true)

  # 5. Parse fields
  if [[ -z "$result_line" ]]; then
    echo "stopped_early|0|0|0|0|no_result_line" > "$result_file"
    rm -rf "$work_dir"
    return 0
  fi

  local status iterations
  status=$(echo "$result_line" | sed 's/.*status=\([a-z_]*\).*/\1/')
  iterations=$(echo "$result_line" | sed 's/.*iterations=\([0-9]*\).*/\1/')

  # 6. Validate convergence — check for false convergence
  if [[ "$status" == "converged" && "$iterations" -le 1 ]]; then
    local post_hash
    post_hash=$(md5 -q "${work_dir}/plan.md")
    if [[ "$pre_hash" == "$post_hash" ]]; then
      echo "stopped_early|${iterations}|0|0|0|false_convergence" > "$result_file"
      rm -rf "$work_dir"
      return 0
    fi
  fi

  # 7. Quality evaluation — diff check + checkpoints
  # 7a. Plan improved? (≥3 substantive diff lines)
  local diff_lines plan_improved=0
  if [[ -f "${work_dir}/plan.md" ]]; then
    local diff_output
    diff_output=$(diff -B -w "${FIXTURES_DIR}/${fixture}.md" "${work_dir}/plan.md" 2>/dev/null || true)
    diff_lines=$(echo "$diff_output" | grep '^[<>]' | grep -v '^[<>][[:space:]]*$' | wc -l | tr -d ' ')
  else
    diff_lines=0
  fi
  if [[ "$diff_lines" -ge 3 ]]; then
    plan_improved=1
  fi

  # 7b. Checkpoints passed?
  local checkpoint_result checkpoints_passed checkpoints_total
  if [[ -f "${work_dir}/plan.md" ]]; then
    checkpoint_result=$(run_checkpoints "$fixture" "${work_dir}/plan.md")
  else
    checkpoint_result="0/0"
  fi
  checkpoints_passed=${checkpoint_result%/*}
  checkpoints_total=${checkpoint_result#*/}

  # 7c. Combined quality criterion: improved AND ≥50% checkpoints
  local quality=0
  local half=$(( (checkpoints_total + 1) / 2 ))
  if [[ "$plan_improved" -eq 1 && "$checkpoints_passed" -ge "$half" ]]; then
    quality=1
  fi

  # 8. Write result
  echo "${status}|${iterations}|${quality}|${checkpoints_passed}|${checkpoints_total}|ok" > "$result_file"
  rm -rf "$work_dir"
}

# ── run_trial ────────────────────────────────────────────────────────────────
# Runs all fixtures * runs IN PARALLEL and produces a score.
# Returns via stdout: score|avg_iterations

run_trial() {
  local trial_number="$1"
  local label="$2"

  # 1. Clean artifacts
  rm -rf "$ARTIFACTS_DIR" && mkdir -p "$ARTIFACTS_DIR"

  # 2. Deploy prompt once (all parallel runs share the same prompt version)
  mkdir -p "$(dirname "$PROMPT_DEST")"
  cp "$PROMPT_SRC" "$PROMPT_DEST"

  # 2b. Validate prompt invariants — if any fail, trial scores 0
  if ! validate_prompt "$PROMPT_SRC"; then
    log "Trial ${trial_number} FAILED: prompt invariant violated — scoring 0"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$trial_number" "$timestamp" "$label" "0" "0.00" "0.0" "0" \
      "INVARIANT_VIOLATION" >> "$RESULTS_TSV"
    echo "0|0.0"
    return 0
  fi

  # 3. Record start time
  local trial_start
  trial_start=$(date +%s)

  # 4. Launch all runs in parallel (throttled to PARALLEL_JOBS)
  local total_expected=$(( ${#FIXTURES[@]} * RUNS_PER_FIXTURE ))
  log "Launching ${total_expected} runs (${PARALLEL_JOBS} parallel)..."

  local job_count=0
  local pids=()
  local run_keys=()

  for fixture in "${FIXTURES[@]}"; do
    for run in $(seq 1 "$RUNS_PER_FIXTURE"); do
      local artifact_prefix="${ARTIFACTS_DIR}/${fixture}_run${run}"

      # Throttle: wait for a slot if at max parallel jobs
      while [[ ${#pids[@]} -ge $PARALLEL_JOBS ]]; do
        local new_pids=()
        for pid in "${pids[@]}"; do
          if kill -0 "$pid" 2>/dev/null; then
            new_pids+=("$pid")
          fi
        done
        pids=("${new_pids[@]}")
        if [[ ${#pids[@]} -ge $PARALLEL_JOBS ]]; then
          sleep 2
        fi
      done

      # Launch run in background
      run_single "$fixture" "$run" "$artifact_prefix" &
      pids+=($!)
      run_keys+=("${fixture}|${run}")
      job_count=$((job_count + 1))
    done
  done

  # 5. Wait for all jobs to complete
  log "All ${job_count} runs launched. Waiting for completion..."
  wait

  # 6. Collect results from files
  local completed=0 converged=0 quality_count=0 total_iterations=0 total_runs=0
  local checkpoint_details=""

  for fixture in "${FIXTURES[@]}"; do
    local fixture_checkpoints_passed=0 fixture_checkpoints_total=0 fixture_runs=0
    for run in $(seq 1 "$RUNS_PER_FIXTURE"); do
      local result_file="${ARTIFACTS_DIR}/${fixture}_run${run}_result.txt"
      local result=""

      if [[ -f "$result_file" ]]; then
        result=$(cat "$result_file")
      else
        result="stopped_early|0|0|0|0|no_result_file"
      fi

      # Parse expanded pipe-separated result
      local status iter quality cp_passed cp_total detail
      status=$(echo "$result" | cut -d'|' -f1)
      iter=$(echo "$result" | cut -d'|' -f2)
      quality=$(echo "$result" | cut -d'|' -f3)
      cp_passed=$(echo "$result" | cut -d'|' -f4)
      cp_total=$(echo "$result" | cut -d'|' -f5)
      detail=$(echo "$result" | cut -d'|' -f6)

      total_runs=$((total_runs + 1))
      fixture_runs=$((fixture_runs + 1))

      # Score: 3 criteria
      if [[ "$status" != "stopped_early" ]]; then
        completed=$((completed + 1))
      fi
      if [[ "$status" == "converged" ]]; then
        converged=$((converged + 1))
      fi
      if [[ "$quality" =~ ^[0-9]+$ && "$quality" -eq 1 ]]; then
        quality_count=$((quality_count + 1))
      fi
      if [[ "$iter" =~ ^[0-9]+$ ]]; then
        total_iterations=$((total_iterations + iter))
      fi
      if [[ "$cp_passed" =~ ^[0-9]+$ ]]; then
        fixture_checkpoints_passed=$((fixture_checkpoints_passed + cp_passed))
      fi
      if [[ "$cp_total" =~ ^[0-9]+$ ]]; then
        fixture_checkpoints_total=$((fixture_checkpoints_total + cp_total))
      fi

      # Log per-run result
      local run_log="${fixture} run ${run}: status=${status} iter=${iter} quality=${quality} checkpoints=${cp_passed}/${cp_total} ${detail}"
      log "$run_log"
      echo "$run_log" >> "${ARTIFACTS_DIR}/summary.txt"
    done

    # Per-fixture checkpoint summary
    if [[ $fixture_runs -gt 0 ]]; then
      checkpoint_details="${checkpoint_details}${fixture}: ${fixture_checkpoints_passed}/${fixture_checkpoints_total} checkpoints across ${fixture_runs} runs; "
    fi
  done

  # 7. Compute score (max 120 = 40 completed + 40 converged + 40 quality)
  local score=$((completed + converged + quality_count))

  # 8. Compute stats
  local convergence_rate="0"
  if [[ $total_runs -gt 0 ]]; then
    convergence_rate=$(awk "BEGIN { printf \"%.2f\", ${converged}/${total_runs} }")
  fi

  local avg_iterations="0"
  if [[ $total_runs -gt 0 ]]; then
    avg_iterations=$(awk "BEGIN { printf \"%.1f\", ${total_iterations}/${total_runs} }")
  fi

  local duration=$(( $(date +%s) - trial_start ))

  # 9. Append to results.tsv
  if [[ ! -f "$RESULTS_TSV" ]]; then
    printf 'trial\ttimestamp\tlabel\tscore\tconvergence_rate\tavg_iterations\tduration_sec\tnotes\n' > "$RESULTS_TSV"
  fi
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$trial_number" "$timestamp" "$label" "$score" "$convergence_rate" "$avg_iterations" "$duration" \
    "completed=${completed} converged=${converged} quality=${quality_count} runs=${total_runs} ${checkpoint_details}" >> "$RESULTS_TSV"

  log "Trial ${trial_number} complete: score=${score}/120 completed=${completed} converged=${converged} quality=${quality_count} avg_iter=${avg_iterations} duration=${duration}s"

  # 10. Return score and avg_iterations
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

CURRENT SCORE: ${current_score}/120
BEST SCORE:    ${best_score}/120

SCORING (3 criteria, 40 points each, max 120):
1. COMPLETED (40): The run finished without crashing or timing out.
2. CONVERGED (40): The skill declared convergence (a sub-agent responded CONVERGED).
3. QUALITY (40): The skill made substantive edits (>=3 diff lines) AND addressed >=50% of
   known fixture flaws (specific issues baked into each test plan that a thorough review should catch).

A prompt that converges quickly but makes no real improvements will score ~80/120 (completed + converged
but 0 quality). A prompt that does thorough reviews but never converges scores ~80/120 (completed + quality
but 0 converged). The optimal prompt must do BOTH: converge efficiently AND produce quality improvements.

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
- Ensuring sub-agents make substantive improvements (not just nitpicks or style changes)
- Ensuring sub-agents declare CONVERGED when the plan is genuinely solid (not too early, not too late)
- Ensuring reviews catch real gaps: missing error handling, vague steps, undefined strategies

Constraints:
- Do NOT change the RESULT: output format (RESULT: status=<status> iterations=<N>)
- Do NOT remove the sub-agent RESULT: prohibition (sub-agents must not emit RESULT: lines)
- Make ONE change, not a full rewrite
- The file must stay at least 10 lines long
- Edit the file directly at: ${PROMPT_SRC}
"

  log "Invoking mutator for trial ${trial_number}..."
  echo "$mutator_prompt" | timeout 120 claude -p \
    --dangerously-skip-permissions \
    --max-budget-usd 1.00 \
    --allowedTools "Read,Edit" \
    > /dev/null 2>&1 || {
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

  log "Starting optimization loop (max ${MAX_TRIALS} trials, score out of 120)"

  for trial in $(seq 1 "$MAX_TRIALS"); do
    log "=== Trial ${trial}/${MAX_TRIALS} ==="

    # a. Run trial (last line of stdout is score|avg_iters; earlier lines are log output)
    local trial_output trial_result
    trial_output=$(run_trial "$trial" "trial_${trial}")
    trial_result=$(echo "$trial_output" | tail -1)
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
      git -C "$REPO_ROOT" commit -m "autoresearch: trial ${trial} — score ${score}/120" --allow-empty || true
      best_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)
      consecutive_no_improve=0
    else
      log "No improvement (score=${score}, best=${best_score}) — reverting"
      git -C "$REPO_ROOT" diff "$PROMPT_SRC" > "$FAILED_DIFF" 2>/dev/null || true
      git -C "$REPO_ROOT" checkout -- "$PROMPT_SRC"
      consecutive_no_improve=$((consecutive_no_improve + 1))
    fi

    # c. Track consecutive perfect (120 = max score)
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
      mkdir -p "$(dirname "$PROMPT_DEST")"
      cp "$PROMPT_SRC" "$PROMPT_DEST"
      mkdir -p "$(dirname "/tmp/autoresearch-single")"
      run_single "$2" "$3" "/tmp/autoresearch-single"
      cat "/tmp/autoresearch-single_result.txt"
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

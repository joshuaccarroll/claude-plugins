#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

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
PARALLEL_JOBS=8
MAX_BUDGET_PER_RUN="3.00"
TIMEOUT_PER_RUN=600
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

# ── Logging helpers ──────────────────────────────────────────────────────────

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
warn() { log "WARN: $*" >&2; }
die()  { log "FATAL: $*" >&2; exit 1; }

# ── validate_prompt ──────────────────────────────────────────────────────────
# Checks invariants against the prompt file. Returns 0 (pass) or 1 (fail).

validate_prompt() {
  local prompt_file="$1"

  # Invariant 1: Prompt instructs creating a plan file if one doesn't exist
  if ! grep -iEq 'write.*plan.*file|write.*to.*\.md|write it to|create.*file|save.*plan.*file|save.*plan|plan.*file' "$prompt_file"; then
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

# ── validate_mutation ────────────────────────────────────────────────────────
# Validates a mutation using fast programmatic checks + an adversarial LLM review.
# Args: $1=prompt file, $2=best_commit (to compare against)
# Returns 0 (pass) or 1 (fail with reason logged).

validate_mutation() {
  local prompt_file="$1"
  local base_commit="${2:-}"

  # 1. Basic invariants (fast, programmatic)
  if ! validate_prompt "$prompt_file"; then
    return 1
  fi

  # 2. File must not be empty or too short
  local line_count
  line_count=$(wc -l < "$prompt_file" | tr -d ' ')
  if [[ ! -s "$prompt_file" || "$line_count" -lt 2 ]]; then
    warn "MUTATION REJECTED: File is empty or too short (${line_count} lines)"
    return 1
  fi

  # Skip comparison checks if no base commit
  if [[ -z "$base_commit" ]]; then
    return 0
  fi

  # 3. Gather context for LLM review
  local old_prompt
  old_prompt=$(git -C "$REPO_ROOT" show "${base_commit}:${prompt_file#${REPO_ROOT}/}" 2>/dev/null || true)
  local new_prompt
  new_prompt=$(cat "$prompt_file")
  local diff_content
  diff_content=$(git -C "$REPO_ROOT" diff "${base_commit}" -- "$prompt_file" 2>/dev/null || true)

  local old_words new_words
  old_words=$(echo "$old_prompt" | wc -w | tr -d ' ')
  new_words=$(echo "$new_prompt" | wc -w | tr -d ' ')

  # 4. Adversarial LLM review
  local review_prompt
  review_prompt="You are reviewing a proposed mutation to a prompt we are optimizing. Be permissive — only reject clearly bad mutations.

CONTEXT: The prompt instructs Claude to iteratively review implementation plans using sub-agents. Scoring rewards completion, convergence, and quality checkpoints.

CURRENT BEST (${old_words} words):
${old_prompt}

PROPOSED (${new_words} words):
${new_prompt}

DIFF:
${diff_content}

REJECT only if the mutation is clearly doing one of these:

1. FULL REWRITE: Replaces the entire prompt rather than making a focused change. Restructuring or rewording parts is fine — wholesale replacement is not.

2. GAMING: Actively tries to hack the scoring rather than improve review quality:
   - Tells the agent to skip review or assume the plan is good
   - Biases toward always reporting CONVERGED regardless of plan quality
   - Removes sub-agent iteration entirely
   Note: Improving RESULT: line formatting, adding clarifying examples, or structural changes that help the agent succeed are NOT gaming — they are legitimate improvements.

3. SABOTAGE: Removes core review mechanics (sub-agent spawning, critical analysis, convergence loop).

Length increases are acceptable if they serve a purpose. Minor wording changes, formatting fixes, and structural improvements should PASS.

When in doubt, PASS. Let the trial results determine if the mutation actually helps.

Respond with exactly one line:
PASS — if the mutation seems reasonable
REJECT: <reason> — only if clearly gaming, rewriting, or sabotaging"

  local review_result
  review_result=$(echo "$review_prompt" | timeout 60 claude -p \
    --output-format text \
    --dangerously-skip-permissions 2>/dev/null || echo "REJECT: LLM review failed or timed out")

  # Parse the last non-empty line (in case of preamble)
  local verdict
  verdict=$(echo "$review_result" | grep -iE '^(PASS|REJECT)' | tail -1)

  if [[ -z "$verdict" ]]; then
    warn "MUTATION REVIEW: No clear verdict — treating as REJECT"
    warn "Review output: ${review_result}"
    return 1
  fi

  if echo "$verdict" | grep -iq '^REJECT'; then
    warn "MUTATION REJECTED by LLM reviewer: ${verdict}"
    return 1
  fi

  log "Mutation passed LLM review: ${verdict}"
  return 0
}

# ── run_checkpoints ──────────────────────────────────────────────────────────
# Evaluates fixture-specific quality patterns.
# Outputs one line per pattern: PASS|fixture[idx] or FAIL|fixture[idx]

run_checkpoints() {
  local fixture="$1"
  local reviewed_file="$2"

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
  if [[ -f "$reviewed_file" ]]; then
    plan_content=$(cat "$reviewed_file")
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
  local result_file="${artifact_prefix}_result.txt"

  # 1. Prepare isolated workspace (per-run to support parallel execution)
  local work_dir="/tmp/autoresearch-${fixture}-run${run_number}"
  rm -rf "$work_dir" && mkdir -p "$work_dir"
  cp "${FIXTURES_DIR}/${fixture}.md" "${work_dir}/plan.md"
  local pre_hash
  pre_hash=$(md5 -q "${work_dir}/plan.md")

  # 2. Invoke Claude
  local raw_output exit_code
  raw_output=$(echo "Use the /review-plan skill to review the plan at ${work_dir}/plan.md" | \
    timeout "$TIMEOUT_PER_RUN" claude -p \
    --output-format json \
    --dangerously-skip-permissions \
    --max-budget-usd "$MAX_BUDGET_PER_RUN" \
    --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Task*" 2>&1) || {
      exit_code=$?
      rm -rf "$work_dir"
      if [[ $exit_code -eq 124 ]]; then
        echo "stopped_early|0|timeout" > "$result_file"
        return 0
      fi
      echo "stopped_early|0|error_${exit_code}" > "$result_file"
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
    echo "stopped_early|0|no_result_line" > "$result_file"
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
      echo "stopped_early|${iterations}|false_convergence" > "$result_file"
      rm -rf "$work_dir"
      return 0
    fi
  fi

  # 7. Run checkpoints and save per-pattern results
  local checkpoint_output
  checkpoint_output=$(run_checkpoints "$fixture" "${work_dir}/plan.md")
  echo "$checkpoint_output" > "${artifact_prefix}_checkpoints.txt"

  # 8. Write result file (for parallel collection after wait)
  echo "${status}|${iterations}|ok" > "$result_file"
  rm -rf "$work_dir"
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

  # 3. Deploy prompt once (all parallel runs share the same prompt version)
  mkdir -p "$(dirname "$PROMPT_DEST")"
  cp "$PROMPT_SRC" "$PROMPT_DEST"

  # 4. Launch all runs in parallel (throttled to PARALLEL_JOBS)
  local total_expected=$(( ${#FIXTURES[@]} * RUNS_PER_FIXTURE ))
  log "Launching ${total_expected} runs (${PARALLEL_JOBS} parallel)..."

  local pids=()
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
    done
  done

  # 5. Wait for all jobs to complete
  log "All ${total_expected} runs launched. Waiting for completion..."
  wait

  # 6. Collect results from files
  for fixture in "${FIXTURES[@]}"; do
    for run in $(seq 1 "$RUNS_PER_FIXTURE"); do
      local artifact_prefix="${ARTIFACTS_DIR}/${fixture}_run${run}"
      local result_file="${artifact_prefix}_result.txt"
      local result=""

      if [[ -f "$result_file" ]]; then
        result=$(cat "$result_file")
      else
        result="stopped_early|0|no_result_file"
        echo "$result" > "$result_file"
      fi

      local status detail iter
      status=$(echo "$result" | cut -d'|' -f1)
      iter=$(echo "$result" | cut -d'|' -f2)
      detail=$(echo "$result" | cut -d'|' -f3)

      total_runs=$((total_runs + 1))

      local run_score
      run_score=$(score_result_file "$result_file")
      total_score=$((total_score + run_score))
      total_iterations=$((total_iterations + iter))

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
  local diversity_hint="${5:-}"

  # Build a concise mutator prompt — let the mutator Read files for detail
  local mutator_prompt
  mutator_prompt="You are optimizing a prompt file. Read it, make ONE targeted edit, then stop.

FILE: ${PROMPT_SRC}
SCORE: ${current_score}/120 (best: ${best_score}/120)
SCORING: 40 runs × 3 criteria (completed +1, converged +1, quality checkpoints +1)

Key files you can Read for context:
- ${ARTIFACTS_DIR}/summary.txt — per-run results from the last trial
- ${ARTIFACTS_DIR}/checkpoint_detail.txt — which quality checks are failing

Constraints:
- Make ONE targeted edit to ${PROMPT_SRC}. Not a rewrite.
- Keep it concise — shorter prompts outperform longer ones.
- Do NOT change the RESULT: output format.
- The prompt must still instruct iterative sub-agent review with convergence."

  if [[ -n "$diversity_hint" ]]; then
    mutator_prompt="${mutator_prompt}

${diversity_hint}"
  fi

  log "Invoking mutator for trial ${trial_number}..."

  local mutator_log="${ARTIFACTS_DIR}/mutator_attempt_t${trial_number}.log"
  echo "$mutator_prompt" | timeout 300 claude -p \
    --dangerously-skip-permissions \
    --output-format json \
    --max-budget-usd 2.00 \
    --allowedTools "Read,Edit" > "$mutator_log" 2>&1 || {
      warn "Mutator invocation failed (exit $?)"
    }
  log "Mutator output saved to ${mutator_log}"

  # Verify the RESULT: instruction survived
  if ! grep -q 'RESULT:' "$PROMPT_SRC"; then
    warn "Mutator removed RESULT: instruction — restoring"
    restore_prompt "$best_commit"
    return 1
  fi

  # Check for no-change (identical to best)
  if [[ -n "$best_commit" ]]; then
    local diff_size
    diff_size=$(git -C "$REPO_ROOT" diff "${best_commit}" -- "$PROMPT_SRC" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$diff_size" -eq 0 ]]; then
      warn "Mutator made no changes"
      return 1
    fi
  fi

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

  # Deploy prompt once
  mkdir -p "$(dirname "$PROMPT_DEST")"
  cp "$PROMPT_SRC" "$PROMPT_DEST"

  local pids=()
  for fixture in "${FIXTURES[@]}"; do
    local artifact_prefix="${ARTIFACTS_DIR}/quick/${fixture}"
    run_single "$fixture" 0 "$artifact_prefix" &
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
  local best_score="${1:-0}"
  local best_avg_iters="${2:-999}"
  local best_commit="${3:-}"
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

    # e. Invoke mutator with up to 3 attempts, then stop if all fail
    if [[ $trial -lt $MAX_TRIALS ]]; then
      local mutation_accepted=false
      local max_mutation_attempts=3
      local mutation_attempt=0
      local diversity_hint=""

      while [[ $mutation_attempt -lt $max_mutation_attempts ]]; do
        mutation_attempt=$((mutation_attempt + 1))
        log "Mutation attempt ${mutation_attempt}/${max_mutation_attempts}..."

        # Invoke mutator
        if ! invoke_mutator "$trial" "$score" "$best_score" "$best_commit" "$diversity_hint"; then
          warn "Mutator failed to produce a change (attempt ${mutation_attempt})"
          diversity_hint="IMPORTANT: Previous attempt failed to produce any change. You MUST edit the file. Read it, identify one specific improvement, and use the Edit tool."
          continue
        fi

        # Validate mutation
        if ! validate_mutation "$PROMPT_SRC" "$best_commit"; then
          warn "Mutation failed validation (attempt ${mutation_attempt})"
          git -C "$REPO_ROOT" diff "${best_commit}" -- "$PROMPT_SRC" > "$FAILED_DIFFS_DIR/rejected_$(date +%s).diff" 2>/dev/null || true
          restore_prompt "$best_commit"
          diversity_hint="IMPORTANT: Previous mutation was rejected by the reviewer. Try a different approach — focus on making the review process itself better, not just formatting."
          continue
        fi

        # Quick-reject
        local quick_score
        quick_score=$(run_quick_check)
        local quick_threshold=$(( best_score * 6 / 100 ))
        if [[ "$quick_score" -lt "$quick_threshold" ]]; then
          warn "Quick-reject: score ${quick_score} < threshold ${quick_threshold} (attempt ${mutation_attempt})"
          git -C "$REPO_ROOT" diff "${best_commit}" -- "$PROMPT_SRC" > "$FAILED_DIFFS_DIR/failed_$(date +%s).diff" 2>/dev/null || true
          restore_prompt "$best_commit"
          diversity_hint="IMPORTANT: Previous mutation passed review but scored poorly in quick-check. Try a completely different approach."
          continue
        fi

        # All checks passed
        mutation_accepted=true
        break
      done

      if [[ "$mutation_accepted" == "true" ]]; then
        git -C "$REPO_ROOT" add "$PROMPT_SRC"
        git -C "$REPO_ROOT" commit -m "autoresearch: trial ${trial} mutation" --allow-empty || true
      else
        log "All ${max_mutation_attempts} mutation attempts failed — cannot improve further"
        log "========================================"
        log "Optimization stopped: mutator exhausted"
        log "Best score:          ${best_score}/120"
        log "Best avg iterations: ${best_avg_iters}"
        log "Best commit:         ${best_commit:-none}"
        log "========================================"
        break
      fi
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
      run_loop "${2:-0}" "${3:-999}" "${4:-}"
      ;;
    resume)
      # Usage: $0 resume <best_score> <best_commit>
      [[ -n "${2:-}" && -n "${3:-}" ]] || die "Usage: $0 resume <best_score> <best_commit>"
      log "Resuming from score ${2} at commit ${3}"
      run_loop "$2" "999" "$3"
      ;;
    *)
      echo "Usage: $0 {single|trial|loop|resume} [args...]"
      exit 1
      ;;
  esac
}

main "$@"

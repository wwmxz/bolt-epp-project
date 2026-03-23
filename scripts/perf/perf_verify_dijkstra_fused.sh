#!/usr/bin/env bash
set -uo pipefail

#############################################################################
# Performance Comparison: Dijkstra with Fused BOLT+EPP Data
# Compares: Baseline vs BOLT vs FUSED+BOLT vs EPP-only
#############################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULT_DIR="${ROOT_DIR}/results/verify_dijkstra"
CSV_FILE="${RESULT_DIR}/performance_comparison_fused.csv"

BASE_BIN="${RESULT_DIR}/dijkstra_base"
BOLT_OPT="${RESULT_DIR}/dijkstra_bolt_opt"
FUSED_BOLT_OPT="${RESULT_DIR}/dijkstra_fused_bolt_opt"
EPP_ONLY_OPT="${RESULT_DIR}/dijkstra_epp_bolt_opt"

# Check for input file
INPUT_FILE=""
if [[ -f "${RESULT_DIR}/input.dat" ]]; then
  INPUT_FILE="${RESULT_DIR}/input.dat"
elif [[ -f "${ROOT_DIR}/llvm-test-suite/MultiSource/Benchmarks/MiBench/network-dijkstra/input.dat" ]]; then
  INPUT_FILE="${ROOT_DIR}/llvm-test-suite/MultiSource/Benchmarks/MiBench/network-dijkstra/input.dat"
  cp "${INPUT_FILE}" "${RESULT_DIR}/"
fi

RUNS=10

if [[ ! -f "${BASE_BIN}" ]] || [[ ! -f "${BOLT_OPT}" ]] || [[ ! -f "${FUSED_BOLT_OPT}" ]] || [[ ! -f "${EPP_ONLY_OPT}" ]]; then
  echo "ERROR: Missing optimized binaries. Run ./verify_dijkstra.sh first" >&2
  exit 1
fi

echo "==========================================="
echo "Performance Verification: network-dijkstra (${RUNS} runs each)"
echo "Compare: Baseline vs BOLT vs FUSED+BOLT vs EPP-only"
echo "==========================================="
echo

# Function to measure performance
measure_perf() {
  local binary="$1"
  local label="$2"
  local times=()
  local rows=()
  local i
  local start_ns
  local end_ns
  local elapsed
  local rc
  local success=0
  local failed=0
  local avg
  local stddev
  local fail_rate
  local safe_label
  local raw_file
  
  echo "Measuring ${label}..." >&2
  for i in $(seq 1 ${RUNS}); do
    start_ns=$(date +%s%N)
    cd "${RESULT_DIR}"
    timeout 30s "${binary}" ${INPUT_FILE} >/dev/null 2>&1
    rc=$?
    cd - >/dev/null
    end_ns=$(date +%s%N)
    elapsed=$(echo "scale=6; ($end_ns - $start_ns) / 1000000000" | bc 2>/dev/null || echo "0.001")

    if [[ ${rc} -eq 0 ]]; then
      success=$((success + 1))
      times+=("${elapsed}")
      rows+=("${i},${elapsed},ok")
    else
      failed=$((failed + 1))
      rows+=("${i},${elapsed},rc_${rc}")
    fi
  done

  if [[ ${success} -gt 0 ]]; then
    avg=$(printf '%s\n' "${times[@]}" | awk '{sum+=$1; n+=1} END {if (n>0) printf "%.6f", sum/n; else print "0"}')
    stddev=$(printf '%s\n' "${times[@]}" | awk '{x[NR]=$1; sum+=$1} END {if (NR>1) {mean=sum/NR; for(i=1;i<=NR;i++) ss+=(x[i]-mean)^2; printf "%.6f", sqrt(ss/NR)} else {print "0.000000"}}')
  else
    avg="0.000000"
    stddev="0.000000"
  fi

  fail_rate=$(awk -v f="${failed}" -v r="${RUNS}" 'BEGIN {if (r>0) printf "%.2f", (f/r)*100; else print "0.00"}')

  safe_label=$(echo "${label}" | sed -E 's/[^A-Za-z0-9_]+/_/g')
  raw_file="${RESULT_DIR}/raw_runs_${safe_label}.csv"
  {
    echo "run,elapsed_s,status"
    printf '%s\n' "${rows[@]}"
  } > "${raw_file}"

  echo "${avg} ${stddev} ${fail_rate} ${raw_file}"
}

# Measure all variants
read -r BASE_TIME BASE_STD BASE_FAIL BASE_RAW < <(measure_perf "${BASE_BIN}" "Baseline")
read -r BOLT_TIME BOLT_STD BOLT_FAIL BOLT_RAW < <(measure_perf "${BOLT_OPT}" "BOLT")
read -r FUSED_TIME FUSED_STD FUSED_FAIL FUSED_RAW < <(measure_perf "${FUSED_BOLT_OPT}" "FUSED+BOLT")
read -r EPP_TIME EPP_STD EPP_FAIL EPP_RAW < <(measure_perf "${EPP_ONLY_OPT}" "EPP-only")

echo

# Calculate improvements
BOLT_IMPROVE=$(echo "${BASE_TIME} ${BOLT_TIME}" | awk '{if($1>0) printf "%.2f", ($1-$2)/$1*100; else print "0"}')
FUSED_IMPROVE=$(echo "${BASE_TIME} ${FUSED_TIME}" | awk '{if($1>0) printf "%.2f", ($1-$2)/$1*100; else print "0"}')
EPP_IMPROVE=$(echo "${BASE_TIME} ${EPP_TIME}" | awk '{if($1>0) printf "%.2f", ($1-$2)/$1*100; else print "0"}')

# Calculate deltas
FUSED_vs_BOLT=$(echo "${BOLT_TIME} ${FUSED_TIME}" | awk '{if($1>0) printf "%.2f", ($1-$2)/$1*100; else print "0"}')
FUSED_vs_EPP=$(echo "${EPP_TIME} ${FUSED_TIME}" | awk '{if($1>0) printf "%.2f", ($1-$2)/$1*100; else print "0"}')
BOLT_vs_EPP=$(echo "${EPP_TIME} ${BOLT_TIME}" | awk '{if($1>0) printf "%.2f", ($1-$2)/$1*100; else print "0"}')

# Save CSV
cat > "${CSV_FILE}" <<EOF
Variant,AvgTime(s),StdDev(s),FailRate(%),Improvement%,vs_Baseline%,RawRunsFile
Baseline,${BASE_TIME},${BASE_STD},${BASE_FAIL},0.00,0.00,${BASE_RAW}
BOLT,${BOLT_TIME},${BOLT_STD},${BOLT_FAIL},${BOLT_IMPROVE},${BOLT_IMPROVE},${BOLT_RAW}
FUSED+BOLT,${FUSED_TIME},${FUSED_STD},${FUSED_FAIL},${FUSED_IMPROVE},${FUSED_IMPROVE},${FUSED_RAW}
EPP-only,${EPP_TIME},${EPP_STD},${EPP_FAIL},${EPP_IMPROVE},${EPP_IMPROVE},${EPP_RAW}
EOF

# Display results
echo "==========================================="
echo "Performance Results (${RUNS} runs average)"
echo "==========================================="
echo
printf "%-40s %s\n" "Variant" "Time (s) | Improve | vs Baseline"
echo "------------------------------------------------------------"
printf "%-40s %.4fs | %6s%% | %6s%%\n" "Baseline:" "${BASE_TIME}" "-" "-"
printf "%-40s %.4fs | %6s%% | %6s%%\n" "BOLT:" "${BOLT_TIME}" "${BOLT_IMPROVE}" "${BOLT_IMPROVE}"
printf "%-40s %.4fs | %6s%% | %6s%%\n" "FUSED+BOLT (new):" "${FUSED_TIME}" "${FUSED_IMPROVE}" "${FUSED_IMPROVE}"
printf "%-40s %.4fs | %6s%% | %6s%%\n" "EPP-only (old):" "${EPP_TIME}" "${EPP_IMPROVE}" "${EPP_IMPROVE}"
echo
echo "Stability summary:"
echo "  Baseline:   std=${BASE_STD}s, fail=${BASE_FAIL}%"
echo "  BOLT:       std=${BOLT_STD}s, fail=${BOLT_FAIL}%"
echo "  FUSED+BOLT: std=${FUSED_STD}s, fail=${FUSED_FAIL}%"
echo "  EPP-only:   std=${EPP_STD}s, fail=${EPP_FAIL}%"
echo

echo "Key deltas:"
echo "------------------------------------------"
printf "  FUSED vs BOLT:  %s%% %s\n" "${FUSED_vs_BOLT}" \
  "$(if (( $(echo "${FUSED_vs_BOLT} > 0" | bc -l) )); then echo "better"; else echo "worse"; fi)"
printf "  FUSED vs EPP:   %s%% %s\n" "${FUSED_vs_EPP}" \
  "$(if (( $(echo "${FUSED_vs_EPP} > 0" | bc -l) )); then echo "better"; else echo "worse"; fi)"
printf "  BOLT vs EPP:    %s%% %s\n" "${BOLT_vs_EPP}" \
  "$(if (( $(echo "${BOLT_vs_EPP} > 0" | bc -l) )); then echo "BOLT better"; else echo "EPP better"; fi)"
echo

echo "Best variant:"
if (( $(echo "${FUSED_IMPROVE} > ${BOLT_IMPROVE} && ${FUSED_IMPROVE} > ${EPP_IMPROVE}" | bc -l) )); then
  echo "  FUSED+BOLT (fusion strategy) is best."
  echo "  Fusion improves optimization quality."
elif (( $(echo "${BOLT_IMPROVE} > ${EPP_IMPROVE}" | bc -l) )); then
  echo "  BOLT is better in this run."
  echo "  FUSED remains close and promising."
else
  echo "  EPP-only is better in this run."
  echo "  Path-level data may already be sufficient here."
fi
echo

echo "Report saved: ${CSV_FILE}"
echo "==========================================="

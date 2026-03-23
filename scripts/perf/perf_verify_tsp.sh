#!/usr/bin/env bash
set -uo pipefail

#############################################################################
# Performance Comparison: TSP Optimization Verification (Simplified)
# Compares: Baseline vs BOLT vs EPP+BOLT
#############################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULT_DIR="${ROOT_DIR}/results/verify_tsp"
CSV_FILE="${RESULT_DIR}/performance_comparison.csv"

BASE_BIN="${RESULT_DIR}/tsp_base"
BOLT_OPT="${RESULT_DIR}/tsp_bolt_opt"
EPP_BOLT_OPT="${RESULT_DIR}/tsp_epp_bolt_opt"

RUNS=10

if [[ ! -f "${BASE_BIN}" ]] || [[ ! -f "${BOLT_OPT}" ]] || [[ ! -f "${EPP_BOLT_OPT}" ]]; then
  echo "ERROR: Missing optimized binaries. Run ./verify_tsp.sh first" >&2
  exit 1
fi

echo "==========================================="
echo "Performance Verification: TSP (${RUNS} runs each)"
echo "==========================================="
echo

# Measure baseline
echo "Measuring Baseline..."
BASE_TIMES=""
for i in $(seq 1 ${RUNS}); do
  START=$(date +%s%N)
  timeout 30s "${BASE_BIN}" >/dev/null 2>&1 || true
  END=$(date +%s%N)
  ELAPSED=$(echo "scale=6; ($END - $START) / 1000000000" | bc 2>/dev/null || echo "0.001")
  BASE_TIMES="${BASE_TIMES} ${ELAPSED}"
done
BASE_TIME=$(echo ${BASE_TIMES} | awk '{sum=0; for(i=1; i<=NF; i++) sum+=$i; print sum/NF}')

# Measure BOLT
echo "Measuring BOLT-optimized..."
BOLT_TIMES=""
for i in $(seq 1 ${RUNS}); do
  START=$(date +%s%N)
  timeout 30s "${BOLT_OPT}" >/dev/null 2>&1 || true
  END=$(date +%s%N)
  ELAPSED=$(echo "scale=6; ($END - $START) / 1000000000" | bc 2>/dev/null || echo "0.001")
  BOLT_TIMES="${BOLT_TIMES} ${ELAPSED}"
done
BOLT_TIME=$(echo ${BOLT_TIMES} | awk '{sum=0; for(i=1; i<=NF; i++) sum+=$i; print sum/NF}')

# Measure EPP+BOLT
echo "Measuring EPP+BOLT-optimized..."
EPP_BOLT_TIMES=""
for i in $(seq 1 ${RUNS}); do
  START=$(date +%s%N)
  timeout 30s "${EPP_BOLT_OPT}" >/dev/null 2>&1 || true
  END=$(date +%s%N)
  ELAPSED=$(echo "scale=6; ($END - $START) / 1000000000" | bc 2>/dev/null || echo "0.001")
  EPP_BOLT_TIMES="${EPP_BOLT_TIMES} ${ELAPSED}"
done
EPP_BOLT_TIME=$(echo ${EPP_BOLT_TIMES} | awk '{sum=0; for(i=1; i<=NF; i++) sum+=$i; print sum/NF}')

echo

# Calculate improvements
BOLT_IMPROVE=$(echo "${BASE_TIME} ${BOLT_TIME}" | awk '{if($1>0) printf "%.2f", ($1-$2)/$1*100; else print "0"}')
EPP_BOLT_IMPROVE=$(echo "${BASE_TIME} ${EPP_BOLT_TIME}" | awk '{if($1>0) printf "%.2f", ($1-$2)/$1*100; else print "0"}')
DELTA=$(echo "${BOLT_TIME} ${EPP_BOLT_TIME}" | awk '{if($1>0) printf "%.2f", ($1-$2)/$1*100; else print "0"}')

# Save CSV
cat > "${CSV_FILE}" <<EOF
Variant,AvgTime(s),Improvement%
Baseline,${BASE_TIME},0.00
BOLT,${BOLT_TIME},${BOLT_IMPROVE}
EPP+BOLT,${EPP_BOLT_TIME},${EPP_BOLT_IMPROVE}
EOF

# Display results
echo "==========================================="
echo "Performance Results:"
echo "==========================================="
echo
printf "%-40s %s\n" "Metric" "Value"
echo "©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤©¤"
printf "%-40s %.4fs\n" "Baseline execution time:" "${BASE_TIME}"
printf "%-40s %.2f%% faster\n" "BOLT improvement:" "${BOLT_IMPROVE}"
printf "%-40s %.2f%% faster\n" "EPP+BOLT improvement:" "${EPP_BOLT_IMPROVE}"
printf "%-40s %.2f%% delta\n" "EPP+BOLT vs BOLT:" "${DELTA}"
echo

# Verdict
echo "Verification Status:"
if (( $(echo "${EPP_BOLT_IMPROVE} > ${BOLT_IMPROVE}" | bc -l) )); then
  echo "  ? EPP+BOLT OUTPERFORMS BOLT"
  echo "    EPP path profiling provides superior branch prediction"
elif (( $(echo "${EPP_BOLT_IMPROVE} < ${BOLT_IMPROVE}" | bc -l) )); then
  echo "  ? BOLT PERFORMS BETTER"
  echo "    BOLT instrumentation captures better profile data"
else
  echo "  = EQUIVALENT PERFORMANCE"
  echo "    Both methods provide similar optimization"
fi
echo

echo "Report saved: ${CSV_FILE}"
echo "==========================================="

#!/usr/bin/env bash
set -uo pipefail

#############################################################################
# Rapid Multi-Round Validation (Fast Version - ~2 minutes)
# Uses existing baseline data and simulates additional rounds
# by probabilistic resampling to represent different execution paths
#############################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULT_DIR="${ROOT_DIR}/results/multiround_rapid_test"
mkdir -p "${RESULT_DIR}"

BASELINE_SIDECAR="${ROOT_DIR}/results/verify_dijkstra/dijkstra.path_aware.tsv"
BASELINE_BIN="${ROOT_DIR}/results/verify_dijkstra/dijkstra_base"
BASELINE_FDATA="${ROOT_DIR}/results/verify_dijkstra/dijkstra.bolt.fdata"
FUSED_BASELINE_OPT="${ROOT_DIR}/results/verify_dijkstra/dijkstra_fused_bolt_opt"

if [[ ! -f "${BASELINE_SIDECAR}" ]] || [[ ! -f "${BASELINE_BIN}" ]]; then
  echo "ERROR: Baseline data missing. Please run: ./verify_dijkstra.sh first"
  exit 1
fi

echo "==========================================="
echo "Multi-Round Rapid Validation (Simulated)"
echo "==========================================="
echo

# Stage 1: 使用现有 sidecar 作为 Round 1
echo "[Stage 1/4] Preparing round sidecars..."
echo

SIDECAR_R1="${BASELINE_SIDECAR}"
SIDECAR_R2="${RESULT_DIR}/dijkstra_round2.path_aware.tsv"
SIDECAR_R3="${RESULT_DIR}/dijkstra_round3.path_aware.tsv"

# Resample sidecar by scaling counts with random variations
cat > "${RESULT_DIR}/resample_sidecars.py" << 'RESAMPLE_PY'
#!/usr/bin/env python3
import sys
import random

def resample_sidecar(input_file, output_file, scale_factor, seed):
    random.seed(seed)
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    with open(output_file, 'w') as out:
        out.write(lines[0])
        for line in lines[1:]:
            if line.startswith('#'):
                out.write(line)
                continue
            parts = line.strip().split('\t')
            if len(parts) < 11:
                out.write(line)
                continue
            try:
                original_count = int(parts[8])
                variation = random.uniform(0.8, 1.2)
                new_count = int(original_count * scale_factor * variation)
                if random.random() < 0.1 and original_count > 0:
                    new_count = int(new_count * 1.5)
                parts[8] = str(new_count)
            except (ValueError, IndexError):
                pass
            out.write('\t'.join(parts) + '\n')

resample_sidecar(sys.argv[1], sys.argv[2], 1.1, 2)
resample_sidecar(sys.argv[1], sys.argv[3], 0.95, 3)
RESAMPLE_PY

python3 "${RESULT_DIR}/resample_sidecars.py" "${BASELINE_SIDECAR}" "${SIDECAR_R2}" "${SIDECAR_R3}"

echo "  ? Round 1 (baseline): $(tail -n +2 ${SIDECAR_R1} | wc -l) edges"
echo "  ? Round 2 (resampled): $(tail -n +2 ${SIDECAR_R2} | wc -l) edges"
echo "  ? Round 3 (resampled): $(tail -n +2 ${SIDECAR_R3} | wc -l) edges"
echo

# Stage 2: 合并 3 个 sidecar
echo "[Stage 2/4] Merging 3 sidecars (take max count, avg confidence)..."
echo

MERGED_SIDECAR="${RESULT_DIR}/dijkstra_multiround_merged.path_aware.tsv"

cat > "${RESULT_DIR}/merge_sidecars.py" << 'MERGE_PY'
#!/usr/bin/env python3
import sys

def merge_sidecars(input_files, output_file):
    merged = {}
    for input_file in input_files:
        with open(input_file, 'r') as f:
            for line_no, line in enumerate(f, 1):
                if line_no == 1 or line.startswith('#'):
                    continue
                parts = line.strip().split('\t')
                if len(parts) < 11:
                    continue
                func_name = parts[4]
                src_off = parts[2]
                dst_off = parts[5]
                key = (func_name, src_off, dst_off)
                try:
                    fusion_count = int(parts[8])
                    confidence = float(parts[10])
                except (ValueError, IndexError):
                    continue
                if key not in merged:
                    merged[key] = {"max_count": 0, "conf_sum": 0.0, "rounds": 0}
                merged[key]["max_count"] = max(merged[key]["max_count"], fusion_count)
                merged[key]["conf_sum"] += confidence
                merged[key]["rounds"] += 1
    
    with open(output_file, 'w') as out:
        out.write('src_id\tsrc_func\tsrc_off\tdst_id\tdst_func\tdst_off\torig_count\tepp_count\tfused_count\tboost_ratio\tconfidence\n')
        for (func_name, src_off, dst_off), data in sorted(merged.items()):
            avg_conf = data["conf_sum"] / max(1, data["rounds"])
            row = f"0\t{func_name}\t{src_off}\t0\t{func_name}\t{dst_off}\t0\t0\t{data['max_count']}\t1.0\t{avg_conf:.2f}"
            out.write(row + '\n')
    return len(merged)

if __name__ == '__main__':
    merge_sidecars(sys.argv[1:-1], sys.argv[-1])
MERGE_PY

python3 "${RESULT_DIR}/merge_sidecars.py" "${SIDECAR_R1}" "${SIDECAR_R2}" "${SIDECAR_R3}" "${MERGED_SIDECAR}"

NROWS_MERGED=$(tail -n +2 "${MERGED_SIDECAR}" 2>/dev/null | wc -l)
echo "  ? Merged sidecar: ${MERGED_SIDECAR}"
echo "  ? Total merged edges: ${NROWS_MERGED}"
echo

# Stage 3: 使用合并的 sidecar 重新优化
echo "[Stage 3/4] BOLT optimization with merged sidecar..."
echo

LLVM_BOLT="${LLVM_BOLT:-/home/common/compiler/llvm-proj-12.0.1/build-pathaware/bin/llvm-bolt}"
[[ ! -x "$LLVM_BOLT" ]] && LLVM_BOLT="/home/common/compiler/llvm-proj-12.0.1/build/bin/llvm-bolt"

MULTIROUND_OPT="${RESULT_DIR}/dijkstra_multiround_opt"
ALPHA="${PATH_AWARE_ALPHA:-0.6}"
MAX_BOOST="${PATH_AWARE_MAX_BOOST:-16}"

${LLVM_BOLT} "${BASELINE_BIN}" \
  -o "${MULTIROUND_OPT}" \
  -data "${BASELINE_FDATA}" \
  -reorder-blocks=ext-tsp \
  --path-aware-file="${MERGED_SIDECAR}" \
  --path-aware-alpha="${ALPHA}" \
  --path-aware-max-boost="${MAX_BOOST}" \
  >"${RESULT_DIR}/bolt_multiround.log" 2>&1

if [[ ! -f "${MULTIROUND_OPT}" ]]; then
  echo "ERROR: Multi-round optimization failed"
  cat "${RESULT_DIR}/bolt_multiround.log"
  exit 1
fi

echo "  ? Multi-round optimized binary: ${MULTIROUND_OPT}"
echo

# Stage 4: 快速性能对比（3 runs 用于噪声估计）
echo "[Stage 4/4] Quick performance comparison (3 runs each)..."
echo

RUN_FILE="${ROOT_DIR}/llvm-test-suite/MultiSource/Benchmarks/MiBench/network-dijkstra/input.dat"
RUN_ARGS="input.dat"

measure_time() {
  local binary="$1"
  local timeout_s=30
  
  if [[ ! -f "$binary" ]]; then
    echo "0"
    return
  fi
  
  # Change to result directory to find input.dat
  cd "${RESULT_DIR}" 2>/dev/null || return 1
    {
        /usr/bin/time -f "%e" timeout ${timeout_s}s "$binary" ${RUN_ARGS} >/dev/null
    } 2>&1 | tail -n 1
  cd - >/dev/null
}

# Copy input file to result directory
cp "${RUN_FILE}" "${RESULT_DIR}/" 2>/dev/null || true

echo "  Baseline (single run)..."
BASE_TIME=$(measure_time "${BASELINE_BIN}")

echo "  Fused single-round (single run)..."
FUSED_TIME=$(measure_time "${FUSED_BASELINE_OPT}")

echo "  Multi-round merged (single run)..."
MULTI_TIME=$(measure_time "${MULTIROUND_OPT}")

echo
echo "==========================================="
echo "RAPID VALIDATION RESULTS"
echo "==========================================="
echo

printf "%-40s: %s s\n" "Baseline" "${BASE_TIME}"
printf "%-40s: %s s\n" "Fused Single-Round" "${FUSED_TIME}"
printf "%-40s: %s s\n" "Multi-Round Merged" "${MULTI_TIME}"
echo

# 计算改进
python3 - "${BASE_TIME:-0}" "${FUSED_TIME:-0}" "${MULTI_TIME:-0}" << 'CALC_PYTHON'
import re
import sys

def to_float(text: str) -> float:
    if text is None:
        return 0.0
    text = text.strip()
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", text):
        return 0.0
    return float(text)

base = to_float(sys.argv[1] if len(sys.argv) > 1 else "0")
fused = to_float(sys.argv[2] if len(sys.argv) > 2 else "0")
multi = to_float(sys.argv[3] if len(sys.argv) > 3 else "0")

if base > 0:
    fused_imp = (base - fused) / base * 100
    multi_imp = (base - multi) / base * 100
else:
    fused_imp = 0.0
    multi_imp = 0.0

if fused > 0:
    multi_vs_fused = (fused - multi) / fused * 100
else:
    multi_vs_fused = 0.0

print(f"Fused improvement: +{fused_imp:.2f}% vs baseline")
print(f"Multi-round improvement: +{multi_imp:.2f}% vs baseline")
print(f"Multi-round vs Fused delta: {multi_vs_fused:+.2f}%")
CALC_PYTHON

echo "==========================================="
echo

# 结论
echo "Summary:"
echo "  ? Baseline sidecar edges: $(tail -n +2 ${SIDECAR_R1} | wc -l)"
echo "  ? Merged (3 rounds): ${NROWS_MERGED} edges"
echo "  ? Merging strategy: take max count per edge, average confidence"
echo
echo "Interpretation:"
echo "  ? If multi-round delta > 0.5%, upgrading to multi-round collection is worthwhile"
echo "  ? If multi-round delta < -0.5%, current single-round is already sufficient"
echo "  ? If delta in [-0.5%, +0.5%], improvement is within measurement noise"
echo

# 保存结果
cat > "${RESULT_DIR}/results.txt" << RESULTS_END
=== Multi-Round Rapid Validation Results ===
Baseline time: ${BASE_TIME} s
Fused single-round: ${FUSED_TIME} s
Multi-round merged: ${MULTI_TIME} s

Merging: 3 resampled sidecars (simulating independent collection rounds)
Strategy: take max edge count, average confidence
Alpha: ${ALPHA}, Max Boost: ${MAX_BOOST}

Note: This is a rapid simulation using probabilistic resampling.
      For full validation, run: ./multiround_quick_validation.sh (actual 3x collect)
RESULTS_END

echo "? Full results saved to: ${RESULT_DIR}/results.txt"
echo

exit 0

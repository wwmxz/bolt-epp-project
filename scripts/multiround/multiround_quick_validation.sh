#!/usr/bin/env bash
set -euo pipefail

#############################################################################
# Multi-Round Quick Validation (Option A)
# Objective: Verify if 3-round EPP collection improves over single-round
# Approach: Run verify_dijkstra.sh 3x independently → merge sidecars → 
#           compare performance (Baseline, BOLT, Single-Round Fused, Multi-Round Fused)
# Expected: Multi-Round performance > Single-Round Fused > BOLT > Baseline
#############################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULT_DIR="${ROOT_DIR}/results/multiround_quick_validation"

mkdir -p "${RESULT_DIR}"

echo "==========================================="
echo "Multi-Round Quick Validation (Option A)"
echo "==========================================="
echo

# 配置变量（与 verify_dijkstra.sh 一致）
BENCHMARK="network-dijkstra"
PATH_AWARE_ALPHA="${PATH_AWARE_ALPHA:-0.6}"
PATH_AWARE_MAX_BOOST="${PATH_AWARE_MAX_BOOST:-16}"

# 单轮结果（已有的基准）
BASELINE_PERF="${ROOT_DIR}/results/verify_dijkstra/dijkstra_base"
BOLT_OPT_BASELINE="${ROOT_DIR}/results/verify_dijkstra/dijkstra_bolt_opt"
FUSED_OPT_BASELINE="${ROOT_DIR}/results/verify_dijkstra/dijkstra_fused_bolt_opt"
SIDECAR_BASELINE="${ROOT_DIR}/results/verify_dijkstra/dijkstra.path_aware.tsv"
INPUT_FILE="${ROOT_DIR}/results/verify_dijkstra/input.dat"
if [[ ! -f "${INPUT_FILE}" ]]; then
  INPUT_FILE="${ROOT_DIR}/llvm-test-suite/MultiSource/Benchmarks/MiBench/network-dijkstra/input.dat"
fi

# 检查基线数据是否存在
if [[ ! -f "${BASELINE_PERF}" ]]; then
  echo "[ERR] Baseline binary not found: ${BASELINE_PERF}"
  echo "      Please first run: verify_dijkstra.sh"
  exit 1
fi

echo "[Stage 1/5] Running 3 independent EPP collections..."
echo

# 存储 3 轮的 sidecar 文件
SIDECARS=()

for ROUND in 1 2 3; do
  ROUND_DIR="${RESULT_DIR}/round_${ROUND}"
  mkdir -p "${ROUND_DIR}"
  
  echo "  Round $ROUND: Running verify_dijkstra.sh -> ${ROUND_DIR}"
  
  # 运行一次完整的 verify_dijkstra.sh，输出到独立的目录
  cd "${ROUND_DIR}"
  bash "${ROOT_DIR}/scripts/verify/verify_dijkstra.sh" >"run_${ROUND}.log" 2>&1
  cd - >/dev/null
  
  # verify_dijkstra.sh 固定输出到 ROOT_DIR/results/verify_dijkstra
  SIDECAR_FILE="${ROOT_DIR}/results/verify_dijkstra/dijkstra.path_aware.tsv"
  
  if [[ -z "${SIDECAR_FILE}" ]] || [[ ! -f "${SIDECAR_FILE}" ]]; then
    echo "    [WRN] Sidecar not found for Round $ROUND, using fallback"
    # 创建空 sidecar（允许继续，但会在后续统计中明显体现）
    SIDECAR_FILE="${ROUND_DIR}/${BENCHMARK}_round_${ROUND}.path_aware.tsv"
    touch "${SIDECAR_FILE}"
  else
    # 保留每轮原始 sidecar 快照，避免被下一轮覆盖
    cp "${SIDECAR_FILE}" "${ROUND_DIR}/dijkstra.path_aware.tsv"
    SIDECAR_FILE="${ROUND_DIR}/dijkstra.path_aware.tsv"
  fi
  
  # 复制到结果目录并记录
  cp "${SIDECAR_FILE}" "${RESULT_DIR}/${BENCHMARK}_round${ROUND}.path_aware.tsv"
  SIDECARS+=("${RESULT_DIR}/${BENCHMARK}_round${ROUND}.path_aware.tsv")
  
  # 统计行数
  NROWS=$(tail -n +2 "${SIDECARS[-1]}" | wc -l 2>/dev/null || echo "0")
  echo "    Round $ROUND sidecar: ${NROWS} edges"
done

echo

echo "[Stage 2/5] Merging 3 sidecars..."
echo

MERGED_SIDECAR="${RESULT_DIR}/${BENCHMARK}_multiround.path_aware.tsv"

# Python 脚本：合并 3 个 sidecar，对每条边取最大权重和平均置信度
cat > "${RESULT_DIR}/merge_sidecars.py" << 'MERGE_PYTHON'
#!/usr/bin/env python3
import sys

def merge_sidecars(sidecar_files, output_file):
    """Merge multiple sidecars: take max fusion_count, average confidence per edge."""
    merged = {}  # key: (func_name, src_off, dst_off)
    
    for sidecar_file in sidecar_files:
        try:
            with open(sidecar_file, 'r') as f:
                for line_no, line in enumerate(f, 1):
                    if line_no == 1 or line.startswith('#'):  # Skip header
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
        except FileNotFoundError:
            print(f"Warning: sidecar not found: {sidecar_file}", file=sys.stderr)
    
    # Write merged output
    with open(output_file, 'w') as out:
        out.write('src_id\tsrc_func\tsrc_off\tdst_id\tdst_func\tdst_off\torig_count\tepp_count\tfused_count\tboost_ratio\tconfidence\n')
        
        for (func_name, src_off, dst_off), data in sorted(merged.items()):
            avg_conf = data["conf_sum"] / max(1, data["rounds"])
            row = f"0\t{func_name}\t{src_off}\t0\t{func_name}\t{dst_off}\t0\t0\t{data['max_count']}\t1.0\t{avg_conf:.2f}"
            out.write(row + '\n')
    
    print(f"Merged {len(merged)} unique edges from {len(sidecar_files)} sidecars", file=sys.stderr)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: merge_sidecars.py <output> <input1> [input2] ...")
        sys.exit(1)
    
    output = sys.argv[1]
    inputs = sys.argv[2:]
    merge_sidecars(inputs, output)
MERGE_PYTHON

python3 "${RESULT_DIR}/merge_sidecars.py" "${MERGED_SIDECAR}" "${SIDECARS[@]}"

echo "  ? Merged sidecar: ${MERGED_SIDECAR}"
NROWS_MERGED=$(tail -n +2 "${MERGED_SIDECAR}" 2>/dev/null | wc -l)
echo "  ? Merged contains ${NROWS_MERGED} edges"
echo

echo "[Stage 3/5] Comparing sidecar coverage..."
echo

# 统计三个 sidecar 的覆盖情况
echo "  Sidecar edge coverage:"
for ROUND in 1 2 3; do
  NROWS=$(tail -n +2 "${RESULT_DIR}/${BENCHMARK}_round${ROUND}.path_aware.tsv" | wc -l 2>/dev/null || echo "0")
  echo "    Round $ROUND: $NROWS edges"
done
echo "    Merged: $NROWS_MERGED edges"
echo

echo "[Stage 4/5] Optimizing with multi-round sidecar..."
echo

# 使用合并的 sidecar 进行 BOLT 优化
MULTIROUND_OPT="${RESULT_DIR}/${BENCHMARK}_multiround_opt"
LLVM_BOLT="${LLVM_BOLT:-${ROOT_DIR}/../llvm-proj-12.0.1/build-pathaware/bin/llvm-bolt}"
if [[ ! -x "${LLVM_BOLT}" ]]; then
  LLVM_BOLT="${ROOT_DIR}/../llvm-proj-12.0.1/build/bin/llvm-bolt"
fi

# 从基线获取 BOLT fdata（已包含 BOLT 的采集）
BOLT_FDATA_BASELINE="${ROOT_DIR}/results/verify_dijkstra/dijkstra.bolt.fdata"

if [[ ! -f "${BOLT_FDATA_BASELINE}" ]]; then
  echo "[ERR] BOLT fdata not found: ${BOLT_FDATA_BASELINE}"
  exit 1
fi

${LLVM_BOLT} "${BASELINE_PERF}" \
  -o "${MULTIROUND_OPT}" \
  -data "${BOLT_FDATA_BASELINE}" \
  -reorder-blocks=ext-tsp \
  --path-aware-file="${MERGED_SIDECAR}" \
  --path-aware-alpha="${PATH_AWARE_ALPHA}" \
  --path-aware-max-boost="${PATH_AWARE_MAX_BOOST}" \
  >"${RESULT_DIR}/multiround_bolt_optimize.log" 2>&1

echo "  ? Multi-round optimized binary: ${MULTIROUND_OPT}"
echo

echo "[Stage 5/5] Performance Comparison (10 runs each)..."
echo

# 定义运行参数（从 verify_dijkstra 获取）
# 性能测试函数
measure_binary() {
  local binary="$1"
  local runs="$2"
  
  if [[ ! -f "$binary" ]]; then
    echo "0"
    return
  fi
  
  local results=()
  local start_ns
  local end_ns
  local elapsed
  local rc
  
  for ((i=0; i<runs; i++)); do
    start_ns=$(date +%s%N)
    if [[ -f "${INPUT_FILE}" ]]; then
      timeout 30s "$binary" "${INPUT_FILE}" >/dev/null 2>&1
      rc=$?
    else
      timeout 30s "$binary" >/dev/null 2>&1
      rc=$?
    fi
    end_ns=$(date +%s%N)

    # 只统计成功运行，避免无效样本污染
    if [[ ${rc} -eq 0 ]]; then
      elapsed=$(echo "scale=6; ($end_ns - $start_ns) / 1000000000" | bc 2>/dev/null || echo "0")
      if [[ -n "${elapsed}" ]] && [[ "${elapsed}" =~ ^[0-9.]+$ ]]; then
        results+=("$elapsed")
      fi
    fi
  done
  
  if [[ ${#results[@]} -gt 0 ]]; then
    python3 -c "
results = [$(echo "${results[@]}" | sed 's/ /, /g')]
print(f'{sum(results)/len(results):.6f}')
"
  else
    echo "0"
  fi
}

# 获取或测量各个二进制的性能
echo "  Measuring baseline (${BASELINE_PERF})..."
BASE_PERF=$(measure_binary "${BASELINE_PERF}" 10)

echo "  Measuring BOLT-single (${BOLT_OPT_BASELINE})..."
BOLT_PERF=$(measure_binary "${BOLT_OPT_BASELINE}" 10)

echo "  Measuring Fused-single (${FUSED_OPT_BASELINE})..."
FUSED_SINGLE_PERF=$(measure_binary "${FUSED_OPT_BASELINE}" 10)

echo "  Measuring Multi-round merged (${MULTIROUND_OPT})..."
MULTIROUND_PERF=$(measure_binary "${MULTIROUND_OPT}" 10)

# 使用 Python 计算改进百分比
cat > "${RESULT_DIR}/calc_stats.py" << 'STATS_PYTHON'
import sys

def calc_improvement(base, new):
    if base == 0:
        return 0
    return (base - new) / base * 100

base_perf = float(sys.argv[1])
bolt_perf = float(sys.argv[2])
fused_single = float(sys.argv[3])
multiround_perf = float(sys.argv[4])

bolt_imp = calc_improvement(base_perf, bolt_perf)
fused_imp = calc_improvement(base_perf, fused_single)
multi_imp = calc_improvement(base_perf, multiround_perf)
multi_vs_fused = calc_improvement(fused_single, multiround_perf)

print(f"{base_perf:.6f} {bolt_perf:.6f} {fused_single:.6f} {multiround_perf:.6f} {bolt_imp:.2f} {fused_imp:.2f} {multi_imp:.2f} {multi_vs_fused:.2f}")
STATS_PYTHON

STATS=$(python3 "${RESULT_DIR}/calc_stats.py" "${BASE_PERF}" "${BOLT_PERF}" "${FUSED_SINGLE_PERF}" "${MULTIROUND_PERF}")
read BASE_P BOLT_P FUSE_P MULTI_P BOLT_I FUSE_I MULTI_I MULTI_VS_I <<< "$STATS"

echo
echo "==========================================="
echo "RESULTS SUMMARY"
echo "==========================================="
echo

printf "%-40s: %10.6f s\n" "Baseline" "${BASE_P}"
printf "%-40s: %10.6f s (+%.2f%%)\n" "BOLT Single" "${BOLT_P}" "${BOLT_I}"
printf "%-40s: %10.6f s (+%.2f%%)\n" "Fused Single-Round" "${FUSE_P}" "${FUSE_I}"
printf "%-40s: %10.6f s (+%.2f%%)\n" "Multi-Round Merged" "${MULTI_P}" "${MULTI_I}"
echo
printf "Multi-Round vs Fused-Single delta:    %.2f%%\n" "${MULTI_VS_I}"
echo
echo "==========================================="
echo

# 保存结果到 CSV
RESULTS_CSV="${RESULT_DIR}/multiround_validation_results.csv"
cat > "${RESULTS_CSV}" << CSV_END
variant,time_seconds,improvement_vs_baseline_pct,notes
Baseline,${BASE_P},0.00,baseline reference
BOLT single,${BOLT_P},${BOLT_I},10 runs avg
Fused single-round,${FUSE_P},${FUSE_I},10 runs avg
Multi-round merged,${MULTI_P},${MULTI_I},3-round collection merged
CSV_END

echo "? Results saved to: ${RESULTS_CSV}"
echo "? Detailed logs: ${RESULT_DIR}/"
echo

# 判定结论
python3 -c "
import sys
multiround = float('${MULTIROUND_PERF}')
fused_single = float('${FUSED_SINGLE_PERF}')

if fused_single > 0:
    delta = (fused_single - multiround) / fused_single * 100
else:
    delta = 0

if multiround < fused_single:
    if delta > 0.5:
        print(f'? SUCCESS: Multi-round provides meaningful improvement (+{delta:.2f}% over single-round)')
    else:
        print(f'? MARGINAL: Multi-round shows slight improvement (+{delta:.2f}%, within noise margin)')
else:
    delta_neg = (multiround - fused_single) / fused_single * 100 if fused_single > 0 else 0
    print(f'? NO GAIN: Multi-round did not improve over single-round fused (+{delta_neg:.2f}%)')
"

echo
exit 0

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/verify/verify_dijkstra.sh"
VERIFY_OUT="${ROOT_DIR}/results/verify_dijkstra"
TS_INPUT="${ROOT_DIR}/llvm-test-suite/MultiSource/Benchmarks/MiBench/network-dijkstra/input.dat"

PERF_RUNS="${PERF_RUNS:-10}"
ALPHA="${PATH_AWARE_ALPHA:-0.6}"
MAX_BOOST="${PATH_AWARE_MAX_BOOST:-16}"

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${ROOT_DIR}/results/multiround_full_validation/${STAMP}"
mkdir -p "${OUT_DIR}"

echo "==========================================="
echo "Option B Full Multi-Round Validation"
echo "==========================================="
echo "Output dir: ${OUT_DIR}"
echo "Perf runs : ${PERF_RUNS}"
echo "Alpha/Max : ${ALPHA}/${MAX_BOOST}"
echo

if [[ ! -x "${VERIFY_SCRIPT}" ]]; then
  echo "ERROR: verify script missing: ${VERIFY_SCRIPT}" >&2
  exit 1
fi

if [[ ! -f "${TS_INPUT}" ]]; then
  echo "ERROR: input file missing: ${TS_INPUT}" >&2
  exit 1
fi

for ROUND in 1 2 3; do
  echo "[Round ${ROUND}/3] Running full verify_dijkstra.sh ..."
  ROUND_DIR="${OUT_DIR}/round_${ROUND}"
  mkdir -p "${ROUND_DIR}"

  bash "${VERIFY_SCRIPT}" >"${ROUND_DIR}/verify.log" 2>&1

  cp "${VERIFY_OUT}/dijkstra.path_aware.tsv" "${ROUND_DIR}/dijkstra.path_aware.tsv"
  cp "${VERIFY_OUT}/dijkstra.bolt.fdata" "${ROUND_DIR}/dijkstra.bolt.fdata"
  cp "${VERIFY_OUT}/dijkstra_base" "${ROUND_DIR}/dijkstra_base"
  cp "${VERIFY_OUT}/dijkstra_bolt_opt" "${ROUND_DIR}/dijkstra_bolt_opt"
  cp "${VERIFY_OUT}/dijkstra_fused_bolt_opt" "${ROUND_DIR}/dijkstra_fused_bolt_opt"

  EDGE_ROWS="$(tail -n +2 "${ROUND_DIR}/dijkstra.path_aware.tsv" | wc -l)"
  echo "  Collected sidecar edges: ${EDGE_ROWS}"
  echo
 done

echo "[Merge] Building merged sidecar from 3 real rounds ..."
MERGED_SIDECAR="${OUT_DIR}/dijkstra.multiround.path_aware.tsv"

python3 - "${MERGED_SIDECAR}" \
  "${OUT_DIR}/round_1/dijkstra.path_aware.tsv" \
  "${OUT_DIR}/round_2/dijkstra.path_aware.tsv" \
  "${OUT_DIR}/round_3/dijkstra.path_aware.tsv" << 'PY'
import sys
from collections import defaultdict

out_file = sys.argv[1]
in_files = sys.argv[2:]

# key = (dst_func, src_off, dst_off)
merged = defaultdict(lambda: {"max_count": 0, "conf_sum": 0.0, "n": 0})
for p in in_files:
    with open(p, "r", encoding="utf-8", errors="ignore") as f:
        for i, line in enumerate(f):
            if i == 0 or line.startswith("#"):
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 11:
                continue
            key = (cols[4], cols[2], cols[5])
            try:
                fused = int(cols[8])
                conf = float(cols[10])
            except ValueError:
                continue
            item = merged[key]
            if fused > item["max_count"]:
                item["max_count"] = fused
            item["conf_sum"] += conf
            item["n"] += 1

with open(out_file, "w", encoding="utf-8") as out:
    out.write("src_id\tsrc_func\tsrc_off\tdst_id\tdst_func\tdst_off\torig_count\tepp_count\tfused_count\tboost_ratio\tconfidence\n")
    for (func, src_off, dst_off), item in sorted(merged.items()):
        avg_conf = item["conf_sum"] / max(1, item["n"])
        out.write(f"0\t{func}\t{src_off}\t0\t{func}\t{dst_off}\t0\t0\t{item['max_count']}\t1.0\t{avg_conf:.2f}\n")

print(len(merged))
PY

MERGED_ROWS="$(tail -n +2 "${MERGED_SIDECAR}" | wc -l)"
BASELINE_ROWS="$(tail -n +2 "${OUT_DIR}/round_1/dijkstra.path_aware.tsv" | wc -l)"

echo "  Baseline rows (round1): ${BASELINE_ROWS}"
echo "  Merged rows           : ${MERGED_ROWS}"
if [[ "${MERGED_ROWS}" -gt "${BASELINE_ROWS}" ]]; then
  echo "  Coverage check        : PASS (merged > baseline)"
else
  echo "  Coverage check        : NOTE (merged <= baseline)"
fi
echo

LLVM_BOLT="${LLVM_BOLT:-/home/common/compiler/llvm-proj-12.0.1/build-pathaware/bin/llvm-bolt}"
if [[ ! -x "${LLVM_BOLT}" ]]; then
  LLVM_BOLT="/home/common/compiler/llvm-proj-12.0.1/build/bin/llvm-bolt"
fi

BASE_BIN="${OUT_DIR}/round_1/dijkstra_base"
BOLT_FDATA="${OUT_DIR}/round_1/dijkstra.bolt.fdata"
MULTI_OPT="${OUT_DIR}/dijkstra_multiround_bolt_opt"


echo "[Optimize] Generating multi-round merged optimized binary ..."
"${LLVM_BOLT}" "${BASE_BIN}" \
  -o "${MULTI_OPT}" \
  -data "${BOLT_FDATA}" \
  -reorder-blocks=ext-tsp \
  --path-aware-file="${MERGED_SIDECAR}" \
  --path-aware-alpha="${ALPHA}" \
  --path-aware-max-boost="${MAX_BOOST}" \
  >"${OUT_DIR}/multiround_bolt_opt.log" 2>&1

if [[ ! -f "${MULTI_OPT}" ]]; then
  echo "ERROR: failed to build multiround optimized binary" >&2
  cat "${OUT_DIR}/multiround_bolt_opt.log" >&2
  exit 1
fi

echo "  Multi-round binary: ${MULTI_OPT}"
echo

echo "[Perf] Comparing Baseline -> BOLT -> Fused-Single -> Multi-Round-Merged ..."

python3 - "${PERF_RUNS}" "${TS_INPUT}" \
  "${OUT_DIR}/round_1/dijkstra_base" \
  "${OUT_DIR}/round_1/dijkstra_bolt_opt" \
  "${OUT_DIR}/round_1/dijkstra_fused_bolt_opt" \
  "${MULTI_OPT}" \
  "${OUT_DIR}" << 'PY'
import csv
import statistics
import subprocess
import sys
import time

runs = int(sys.argv[1])
input_file = sys.argv[2]
base_bin = sys.argv[3]
bolt_bin = sys.argv[4]
fused_bin = sys.argv[5]
multi_bin = sys.argv[6]
out_dir = sys.argv[7]

variants = [
    ("Baseline", base_bin),
    ("BOLT", bolt_bin),
    ("Fused-Single", fused_bin),
    ("Multi-Round-Merged", multi_bin),
]

def bench(bin_path):
    values = []
    for _ in range(runs):
        t0 = time.perf_counter()
        try:
            subprocess.run([bin_path, input_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=30)
            values.append(time.perf_counter() - t0)
        except Exception:
            pass
    if not values:
        return 0.0, 0.0, 100.0
    fail_rate = (runs - len(values)) * 100.0 / runs
    mean = statistics.mean(values)
    stdev = statistics.pstdev(values) if len(values) > 1 else 0.0
    return mean, stdev, fail_rate

rows = []
for name, path in variants:
    mean, stdev, fail_rate = bench(path)
    rows.append((name, path, mean, stdev, fail_rate))

base = rows[0][2] if rows else 0.0

def imp(v):
    if base <= 0:
        return 0.0
    return (base - v) / base * 100.0

summary_csv = f"{out_dir}/perf_summary.csv"
with open(summary_csv, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["variant", "mean_s", "stddev_s", "fail_rate_pct", "improvement_vs_baseline_pct"])
    for name, _, mean, stdev, fail_rate in rows:
        w.writerow([name, f"{mean:.6f}", f"{stdev:.6f}", f"{fail_rate:.2f}", f"{imp(mean):.2f}"])

for name, _, mean, stdev, fail_rate in rows:
    print(f"{name:20s} mean={mean:.6f}s std={stdev:.6f}s fail={fail_rate:.2f}% imp_vs_base={imp(mean):+.2f}%")

if len(rows) >= 4:
    fused = rows[2][2]
    multi = rows[3][2]
    if fused > 0:
        delta = (fused - multi) / fused * 100.0
        print(f"Multi-Round vs Fused-Single delta: {delta:+.2f}%")

print(f"Saved: {summary_csv}")
PY

echo
 echo "[Done] Full validation completed. Artifacts under: ${OUT_DIR}"
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULT_DIR="${ROOT_DIR}/results"
RUN_MANIFEST="${RESULT_DIR}/multisource_run_manifest.tsv"
OUTPUT_CSV="${RESULT_DIR}/performance_multisource.csv"
TMP_DIR="${RESULT_DIR}/.perf_multisource_tmp"
mkdir -p "${TMP_DIR}"

if [[ ! -f "${RUN_MANIFEST}" ]]; then
  echo "error: ${RUN_MANIFEST} not found. Run ./run_multisource.sh first." >&2
  exit 1
fi

echo "Benchmark,Version,Time_ms,Cycles,Instructions,IPC" > "${OUTPUT_CSV}"

run_perf_once() {
  local cwd="$1"
  local bin="$2"
  local args_str="$3"
  local tag="$4"
  local log="${TMP_DIR}/${tag}.log"

  rm -f "${log}"

  read -r -a args_arr <<< "${args_str:-}"

  (
    cd "${cwd}"
    perf stat -x, -e task-clock,cycles,instructions -o "${log}" -- "${bin}" "${args_arr[@]}" >/dev/null 2>&1 || true
  )

  local task_clock cycles inst ipc
  task_clock=$(awk -F, '$0 ~ /task-clock/ {print $1; exit}' "${log}" || true)
  cycles=$(awk -F, '$0 ~ /cycles/ && $0 !~ /task-clock/ {print $1; exit}' "${log}" || true)
  inst=$(awk -F, '$0 ~ /instructions/ {print $1; exit}' "${log}" || true)

  normalize_num() {
    local v="$1"
    if [[ -z "${v}" ]]; then
      echo "N/A"
      return
    fi
    if [[ "${v}" == "<not"* ]] || [[ "${v}" == *"not supported"* ]] || [[ "${v}" == *"not counted"* ]]; then
      echo "N/A"
      return
    fi
    echo "${v//,/}"
  }

  task_clock=$(normalize_num "${task_clock}")
  cycles=$(normalize_num "${cycles}")
  inst=$(normalize_num "${inst}")

  local time_ms="${task_clock}"
  if [[ "${cycles}" != "N/A" && "${inst}" != "N/A" && "${cycles}" != "0" ]]; then
    ipc=$(awk -v i="${inst}" -v c="${cycles}" 'BEGIN { printf "%.4f", i/c }')
  else
    ipc="N/A"
  fi

  echo "${time_ms},${cycles},${inst},${ipc}"
}

bench_one() {
  local name="$1"
  local version="$2"
  local cwd="$3"
  local args_str="$4"
  local bin="$5"

  if [[ ! -x "${bin}" ]]; then
    return
  fi

  echo "Testing ${name} - ${version} ..."
  local metrics
  metrics=$(run_perf_once "${cwd}" "${bin}" "${args_str}" "${name}_${version}")
  echo "${name},${version},${metrics}" >> "${OUTPUT_CSV}"
}

while IFS=$'\t' read -r name cwd run_args base_bin bolt_bin epp_bolt_bin || [[ -n "${name:-}" ]]; do
  [[ "${name}" == "Benchmark" ]] && continue
  [[ -z "${name}" ]] && continue

  bench_one "${name}" "Base" "${cwd}" "${run_args}" "${base_bin}"
  bench_one "${name}" "BOLT-Opt" "${cwd}" "${run_args}" "${bolt_bin}"
  bench_one "${name}" "EPP+BOLT-Opt" "${cwd}" "${run_args}" "${epp_bolt_bin}"
done < "${RUN_MANIFEST}"

rm -rf "${TMP_DIR}"
echo
echo "MultiSource performance test done!"
column -s, -t "${OUTPUT_CSV}"

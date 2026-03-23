#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULT_DIR="${ROOT_DIR}/results"
OUTPUT_CSV="${RESULT_DIR}/performance.csv"
TMP_DIR="${RESULT_DIR}/.perf_tmp"
mkdir -p "${TMP_DIR}"

# 说明：
# 1) 用 -x, 让 perf 输出 CSV，解析稳定
# 2) cycles/instructions 可能因权限或虚拟化缺失，脚本会保留 N/A
# 3) 程序标准输出和错误输出全部静默

echo "Benchmark,Version,Time_ms,Cycles,Instructions,IPC" > "${OUTPUT_CSV}"

run_perf_once() {
    local bin="$1"
    local tag="$2"
    local log="${TMP_DIR}/${tag}.log"

    rm -f "${log}"

    # task-clock 基本可用；cycles/instructions 在 WSL/容器里可能不可用
    perf stat -x, -e task-clock,cycles,instructions -o "${log}" -- "${bin}" >/dev/null 2>&1 || true

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
        # 去掉千分位
        echo "${v//,/}"
    }

    task_clock=$(normalize_num "${task_clock}")
    cycles=$(normalize_num "${cycles}")
    inst=$(normalize_num "${inst}")

    # Time_ms 直接用 task-clock(msec)
    local time_ms="${task_clock}"

    # IPC
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
    local bin="$3"

    if [[ ! -x "${bin}" ]]; then
        return
    fi

    echo "Testing ${name} - ${version} ..."
    local metrics
    metrics=$(run_perf_once "${bin}" "${name}_${version}")
    echo "${name},${version},${metrics}" >> "${OUTPUT_CSV}"
}

for base_bin in "${RESULT_DIR}"/*_base; do
    [[ -e "${base_bin}" ]] || continue

    NAME=$(basename "${base_bin}" _base)

    BASE_BIN="${RESULT_DIR}/${NAME}_base"
    BOLT_BIN="${RESULT_DIR}/${NAME}_bolt_opt"
    EPP_BOLT_BIN="${RESULT_DIR}/${NAME}_epp_bolt_opt"

    bench_one "${NAME}" "Base" "${BASE_BIN}"
    bench_one "${NAME}" "BOLT-Opt" "${BOLT_BIN}"
    bench_one "${NAME}" "EPP+BOLT-Opt" "${EPP_BOLT_BIN}"
done

rm -rf "${TMP_DIR}"
echo
echo "Performance test done!"
column -s, -t "${OUTPUT_CSV}"
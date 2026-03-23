#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS_BUILD_DIR="${ROOT_DIR}/build-ts-multisource"
TS_SRC_ROOT="${ROOT_DIR}/llvm-test-suite"
SUITE_OUT_ROOT="${ROOT_DIR}/results/pathaware_suite"

CLANG="${CLANG:-clang}"
CLANGXX="${CLANGXX:-clang++}"
LLVM_LINK="${LLVM_LINK:-llvm-link}"
LLVM_EPP="${LLVM_EPP:-llvm-epp}"

if [[ -n "${LLVM_BOLT+x}" ]]; then
  LLVM_BOLT="${LLVM_BOLT}"
elif [[ -x "$HOME/compiler/llvm-proj-12.0.1/build-pathaware/bin/llvm-bolt" ]]; then
  LLVM_BOLT="$HOME/compiler/llvm-proj-12.0.1/build-pathaware/bin/llvm-bolt"
else
  LLVM_BOLT="$HOME/compiler/llvm-proj-12.0.1/build/bin/llvm-bolt"
fi

if [[ -n "${PERF2BOLT+x}" ]]; then
  PERF2BOLT="${PERF2BOLT}"
elif [[ -x "$HOME/compiler/llvm-proj-12.0.1/build-pathaware/bin/perf2bolt" ]]; then
  PERF2BOLT="$HOME/compiler/llvm-proj-12.0.1/build-pathaware/bin/perf2bolt"
else
  PERF2BOLT="$HOME/compiler/llvm-proj-12.0.1/build/bin/perf2bolt"
fi

EPP2BOLT_PY="${EPP2BOLT_PY:-${ROOT_DIR}/scripts/tools/epp2bolt.py}"
MERGE_SIDECARS_PY="${MERGE_SIDECARS_PY:-${ROOT_DIR}/scripts/tools/merge_pathaware_sidecars.py}"
OBJDUMP_BIN="${OBJDUMP_BIN:-llvm-objdump}"
PERF_RUNS="${PERF_RUNS:-10}"

if [[ -n "${BOLT_RT_LIB+x}" ]]; then
  BOLT_RT_LIB="${BOLT_RT_LIB}"
elif [[ -f "$HOME/compiler/llvm-proj-12.0.1/build-pathaware/lib/libbolt_rt_instr.a" ]]; then
  BOLT_RT_LIB="$HOME/compiler/llvm-proj-12.0.1/build-pathaware/lib/libbolt_rt_instr.a"
elif [[ -f "$HOME/compiler/llvm-proj-12.0.1/build/lib/libbolt_rt_instr.a" ]]; then
  BOLT_RT_LIB="$HOME/compiler/llvm-proj-12.0.1/build/lib/libbolt_rt_instr.a"
else
  BOLT_RT_LIB=""
fi

PROFILE_MODE="stable"
TESTSET="simple"
BENCH_LIST_FILE=""
BENCHMARKS_INLINE=""
DRY_RUN=0
PROGRESSIVE_ENABLE=0
PROGRESSIVE_ROUNDS="1"
PROGRESSIVE_MODE="hot"
PROGRESSIVE_MERGE_POLICY="maxavg"
PROGRESSIVE_BUDGET="0"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--profile stable|aggressive|custom] [--testset simple|large|custom]
                   [--bench-file path] [--benchmarks "suite|bench|timeout,..."]
                   [--perf-runs N] [--dry-run]
                   [--progressive] [--progressive-rounds N]
                   [--progressive-mode hot|balance|blind]
                   [--progressive-budget N]
                   [--progressive-merge-policy maxavg|coverage-priority]

Defaults:
  --profile stable      => alpha=0.6, max_boost=16
  --testset simple      => testsets/pathaware_simple.list
  --perf-runs 10
  --progressive off     => single-round collection

Examples:
  ./run_pathaware_suite.sh
  ./run_pathaware_suite.sh --profile aggressive --testset large
  ./run_pathaware_suite.sh --testset custom --bench-file testsets/pathaware_custom.list
  ./run_pathaware_suite.sh --benchmarks "MultiSource/Benchmarks/MiBench/network-dijkstra|network-dijkstra|120"
  ./run_pathaware_suite.sh --progressive --progressive-rounds 3 --progressive-mode hot --progressive-budget 0
  ./run_pathaware_suite.sh --progressive --progressive-rounds 3 --progressive-merge-policy coverage-priority
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE_MODE="$2"
      shift 2
      ;;
    --testset)
      TESTSET="$2"
      shift 2
      ;;
    --bench-file)
      BENCH_LIST_FILE="$2"
      shift 2
      ;;
    --benchmarks)
      BENCHMARKS_INLINE="$2"
      shift 2
      ;;
    --perf-runs)
      PERF_RUNS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --progressive)
      PROGRESSIVE_ENABLE=1
      shift
      ;;
    --progressive-rounds)
      PROGRESSIVE_ROUNDS="$2"
      shift 2
      ;;
    --progressive-mode)
      PROGRESSIVE_MODE="$2"
      shift 2
      ;;
    --progressive-budget)
      PROGRESSIVE_BUDGET="$2"
      shift 2
      ;;
    --progressive-merge-policy)
      PROGRESSIVE_MERGE_POLICY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

PATH_AWARE_ENABLE=1
case "${PROFILE_MODE}" in
  stable)
    PATH_AWARE_ALPHA="0.6"
    PATH_AWARE_MAX_BOOST="16"
    ;;
  aggressive)
    PATH_AWARE_ALPHA="1.0"
    PATH_AWARE_MAX_BOOST="48"
    ;;
  custom)
    PATH_AWARE_ALPHA="${PATH_AWARE_ALPHA:-0.6}"
    PATH_AWARE_MAX_BOOST="${PATH_AWARE_MAX_BOOST:-16}"
    ;;
  *)
    echo "ERROR: --profile must be one of stable|aggressive|custom" >&2
    exit 1
    ;;
esac

if ! [[ "${PROGRESSIVE_ROUNDS}" =~ ^[0-9]+$ ]] || [[ "${PROGRESSIVE_ROUNDS}" -lt 1 ]]; then
  echo "ERROR: --progressive-rounds must be a positive integer" >&2
  exit 1
fi

if ! [[ "${PROGRESSIVE_BUDGET}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --progressive-budget must be a non-negative integer" >&2
  exit 1
fi

case "${PROGRESSIVE_MODE}" in
  hot|balance|blind)
    ;;
  *)
    echo "ERROR: --progressive-mode must be one of hot|balance|blind" >&2
    exit 1
    ;;
esac

case "${PROGRESSIVE_MERGE_POLICY}" in
  maxavg|coverage-priority)
    ;;
  *)
    echo "ERROR: --progressive-merge-policy must be one of maxavg|coverage-priority" >&2
    exit 1
    ;;
esac

if [[ "${PROGRESSIVE_ROUNDS}" -gt 1 ]]; then
  PROGRESSIVE_ENABLE=1
fi

if [[ -z "${BENCH_LIST_FILE}" ]]; then
  case "${TESTSET}" in
    simple)
      BENCH_LIST_FILE="${ROOT_DIR}/testsets/pathaware_simple.list"
      ;;
    large)
      BENCH_LIST_FILE="${ROOT_DIR}/testsets/pathaware_large.list"
      ;;
    custom)
      BENCH_LIST_FILE="${ROOT_DIR}/testsets/pathaware_custom.list"
      ;;
    *)
      echo "ERROR: --testset must be one of simple|large|custom" >&2
      exit 1
      ;;
  esac
fi

if [[ ! -f "${BENCH_LIST_FILE}" ]]; then
  echo "ERROR: benchmark list file not found: ${BENCH_LIST_FILE}" >&2
  exit 1
fi

if [[ ! -x "${LLVM_BOLT}" ]]; then
  echo "ERROR: llvm-bolt not executable: ${LLVM_BOLT}" >&2
  exit 1
fi

mkdir -p "${SUITE_OUT_ROOT}"
RUN_TAG="$(date +%Y%m%d_%H%M%S)_${PROFILE_MODE}"
RUN_DIR="${SUITE_OUT_ROOT}/${RUN_TAG}"
mkdir -p "${RUN_DIR}"
SUMMARY_CSV="${RUN_DIR}/summary.csv"

cat > "${SUMMARY_CSV}" <<EOF
benchmark,status,baseline_s,bolt_s,fused_s,epp_s,fused_vs_bolt_percent,bolt_improve_percent,fused_improve_percent,epp_improve_percent,path_aware_rows,result_dir
EOF

measure_perf() {
  local binary="$1"
  local input_args="$2"
  local workdir="$3"
  local runs="$4"
  local timeout_s="$5"

  local times=()
  local i
  local start_ns
  local end_ns
  local elapsed
  local rc

  for i in $(seq 1 "${runs}"); do
    start_ns=$(date +%s%N)
    local cmd
    cmd="$(printf '%q ' "${binary}")"
    if [[ -n "${input_args}" ]]; then
      cmd+="${input_args}"
    fi
    (cd "${workdir}" && timeout "${timeout_s}" bash -lc "${cmd}" >/dev/null 2>&1)
    rc=$?
    end_ns=$(date +%s%N)
    elapsed=$(echo "scale=6; (${end_ns} - ${start_ns}) / 1000000000" | bc 2>/dev/null || echo "0.001")
    if [[ ${rc} -eq 0 ]]; then
      times+=("${elapsed}")
    fi
  done

  if [[ ${#times[@]} -eq 0 ]]; then
    echo "0.000000"
    return
  fi

  printf '%s\n' "${times[@]}" | awk '{sum+=$1; n+=1} END {if (n>0) printf "%.6f", sum/n; else print "0.000000"}'
}

run_one_benchmark() {
  local suite_rel="$1"
  local benchmark="$2"
  local timeout_s="$3"

  local src_dir="${TS_SRC_ROOT}/${suite_rel}"
  local bin_dir="${TS_BUILD_DIR}/${suite_rel}"
  local ts_bin="${bin_dir}/${benchmark}"
  local result_dir="${RUN_DIR}/${benchmark}"
  local bolt_runtime_args=()
  local perf_timeout_s="${timeout_s}"
  if [[ "${perf_timeout_s}" -lt 30 ]]; then
    perf_timeout_s=30
  fi

  if [[ -n "${BOLT_RT_LIB}" ]] && [[ -f "${BOLT_RT_LIB}" ]]; then
    bolt_runtime_args=(--runtime-instrumentation-lib="${BOLT_RT_LIB}")
  fi

  mkdir -p "${result_dir}"

  if [[ ! -d "${src_dir}" ]]; then
    echo "WARN: source directory missing: ${src_dir}" >&2
    echo "${benchmark},missing-src,0,0,0,0,0,0,0,0,0,${result_dir}" >> "${SUMMARY_CSV}"
    return
  fi

  if [[ ! -f "${ts_bin}" ]]; then
    echo "INFO: test-suite binary missing (will self-compile): ${ts_bin}" >&2
  fi

  echo ""
  echo "=== [${benchmark}] ${suite_rel} ==="

  mapfile -t src_files < <(find "${src_dir}" -maxdepth 1 \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.C' \) | sort)
  if [[ ${#src_files[@]} -eq 0 ]]; then
    echo "WARN: no source files found for ${benchmark}" >&2
    echo "${benchmark},missing-source-files,0,0,0,0,0,0,0,0,0,${result_dir}" >> "${SUMMARY_CSV}"
    return
  fi

  local has_cxx=0
  local sf
  for sf in "${src_files[@]}"; do
    case "${sf}" in
      *.cc|*.cpp|*.cxx|*.C)
        has_cxx=1
        break
        ;;
    esac
  done

  local build_compiler="${CLANG}"
  if [[ "${has_cxx}" == "1" ]]; then
    build_compiler="${CLANGXX}"
  fi

  local cmake_file="${src_dir}/CMakeLists.txt"
  local cppflags=""
  local cflags=""
  local ldflags=""
  local run_args=""

  if [[ -f "${cmake_file}" ]]; then
    cppflags=$(grep -E "list\(APPEND CPPFLAGS" "${cmake_file}" | sed -E "s/^[[:space:]]*list\(APPEND CPPFLAGS[[:space:]]+//; s/[[:space:]]*\)[[:space:]]*$//" 2>/dev/null || true)
    cflags=$(grep -E "list\(APPEND CFLAGS" "${cmake_file}" | sed -E "s/^[[:space:]]*list\(APPEND CFLAGS[[:space:]]+//; s/[[:space:]]*\)[[:space:]]*$//" 2>/dev/null || true)
    ldflags=$(grep -E "list\(APPEND LDFLAGS" "${cmake_file}" | sed -E "s/^[[:space:]]*list\(APPEND LDFLAGS[[:space:]]+//; s/[[:space:]]*\)[[:space:]]*$//" 2>/dev/null || true)
    run_args=$(grep -E "set\(RUN_OPTIONS" "${cmake_file}" | sed -E "s/^[[:space:]]*set\(RUN_OPTIONS[[:space:]]+//; s/[[:space:]]*\)[[:space:]]*$//" 2>/dev/null | head -1 || true)
  fi

  if [[ "${run_args}" == *'${INPUT}'* ]]; then
    local input_arg=""
    if [[ -f "${src_dir}/short.cnf" ]]; then
      input_arg="short.cnf"
    elif [[ -f "${src_dir}/small.cnf" ]]; then
      input_arg="small.cnf"
    elif [[ -f "${src_dir}/long.cnf" ]]; then
      input_arg="long.cnf"
    fi
    if [[ -n "${input_arg}" ]]; then
      run_args="${run_args//\$\{INPUT\}/${input_arg}}"
    fi
  fi

  local base_bin="${result_dir}/${benchmark}_base"
  local bc_file="${result_dir}/${benchmark}.bc"
  local tmp_bc_dir="${result_dir}/.bc_temp"
  local epp_profile="${result_dir}/${benchmark}.profile"
  local epp_bc="${result_dir}/${benchmark}.epp.bc"
  local epp_exe="${result_dir}/${benchmark}_epp_exe"
  local epp_paths="${result_dir}/${benchmark}_paths.txt"
  local bolt_instr="${result_dir}/${benchmark}_bolt_instr"
  local bolt_fdata="${result_dir}/${benchmark}.bolt.fdata"
  local bolt_opt="${result_dir}/${benchmark}_bolt_opt"
  local epp_preagg="${result_dir}/${benchmark}.epp.preagg.txt"
  local epp_fdata="${result_dir}/${benchmark}.epp.fdata"
  local fused_fdata="${result_dir}/${benchmark}.fused.fdata"
  local path_aware_file="${result_dir}/${benchmark}.path_aware.tsv"
  local fused_opt="${result_dir}/${benchmark}_fused_bolt_opt"
  local epp_opt="${result_dir}/${benchmark}_epp_bolt_opt"
  local progressive_sidecar="${result_dir}/${benchmark}.path_aware.progressive.tsv"
  local progressive_state="${result_dir}/${benchmark}.incremental.state"

  discover_profile_file() {
    local scan_dir="$1"
    local bench_name="$2"
    local candidate
    local best=""
    local best_mtime=0
    local mtime=0
    for candidate in "${scan_dir}"/*.profile "${scan_dir}"/*profile* "${scan_dir}"/*"${bench_name}"*; do
      if [[ -f "${candidate}" ]] && file "${candidate}" 2>/dev/null | grep -q "ASCII text"; then
        mtime=$(stat -c %Y "${candidate}" 2>/dev/null || echo 0)
        if [[ "${mtime}" -ge "${best_mtime}" ]]; then
          best_mtime="${mtime}"
          best="${candidate}"
        fi
      fi
    done
    if [[ -n "${best}" ]]; then
      echo "${best}"
      return 0
    fi
    return 1
  }

  # Stage 1: compile baseline
  "${build_compiler}" -O2 -g ${cppflags} ${cflags} "${src_files[@]}" -o "${base_bin}" ${ldflags} -Wl,--emit-relocs >"${result_dir}/compile_base.log" 2>&1
  if [[ ! -f "${base_bin}" ]]; then
    echo "WARN: baseline compile failed for ${benchmark}" >&2
    echo "${benchmark},baseline-compile-failed,0,0,0,0,0,0,0,0,0,${result_dir}" >> "${SUMMARY_CSV}"
    return
  fi

  # Stage 2: bitcode build
  rm -rf "${tmp_bc_dir}"
  mkdir -p "${tmp_bc_dir}"
  local bc_files=()
  local src
  for src in "${src_files[@]}"; do
    local bname
    bname="$(basename "${src}")"
    local bc_out="${tmp_bc_dir}/${bname%.*}.bc"
    "${build_compiler}" -g -emit-llvm -c ${cppflags} ${cflags} "${src}" -o "${bc_out}" >"${result_dir}/compile_bc_${bname}.log" 2>&1
    bc_files+=("${bc_out}")
  done

  if [[ ${#bc_files[@]} -gt 1 ]]; then
    "${LLVM_LINK}" "${bc_files[@]}" -o "${bc_file}" >"${result_dir}/link_bc.log" 2>&1
  else
    cp "${bc_files[0]}" "${bc_file}"
  fi

  # Stage 3: epp profile
  local round1_mode="single"
  if [[ "${PROGRESSIVE_ENABLE}" == "1" ]] && [[ "${PROGRESSIVE_ROUNDS}" -gt 1 ]]; then
    round1_mode="collect"
  fi

  "${LLVM_EPP}" "${bc_file}" \
    -o "${epp_profile}" \
    --round-id 1 \
    --round-mode "${round1_mode}" \
    --round-budget "${PROGRESSIVE_BUDGET}" \
    --incremental-state "${progressive_state}" \
    >"${result_dir}/epp_instrument.log" 2>&1
  if [[ -f "${bc_file%.bc}.epp.bc" ]]; then
    epp_bc="${bc_file%.bc}.epp.bc"
  fi

  "${build_compiler}" "${epp_bc}" -o "${epp_exe}" -lepp-rt ${ldflags} >"${result_dir}/epp_link.log" 2>&1

  if [[ -n "${run_args}" ]]; then
    local token prev
    prev=""
    for token in ${run_args}; do
      case "${token}" in
        '<'|'>'|'>>'|'2>'|'2>>'|'1>'|'1>>')
          prev="redir"
          continue
          ;;
      esac
      if [[ "${prev}" == "redir" ]]; then
        if [[ -f "${src_dir}/${token}" ]]; then
          cp "${src_dir}/${token}" "${result_dir}/" 2>/dev/null || true
        elif [[ -f "${bin_dir}/${token}" ]]; then
          cp "${bin_dir}/${token}" "${result_dir}/" 2>/dev/null || true
        fi
        prev=""
        continue
      fi
      if [[ "${token}" != -* ]] && [[ "${token}" != *":"* ]]; then
        if [[ -f "${src_dir}/${token}" ]]; then
          cp "${src_dir}/${token}" "${result_dir}/" 2>/dev/null || true
        elif [[ -f "${bin_dir}/${token}" ]]; then
          cp "${bin_dir}/${token}" "${result_dir}/" 2>/dev/null || true
        fi
      fi
    done
  fi

  if [[ "${benchmark}" == "sqlite3" ]] && [[ ! -f "${result_dir}/test15.sql" ]]; then
    if command -v tclsh >/dev/null 2>&1; then
      (cd "${result_dir}" && tclsh "${src_dir}/speedtest.tcl" >/dev/null 2>&1) || \
      (cd "${result_dir}" && tclsh "${src_dir}/smalltest.tcl" >/dev/null 2>&1) || true
    fi
  fi

  local epp_cmd
  epp_cmd="$(printf '%q ' "${epp_exe}")"
  if [[ -n "${run_args}" ]]; then
    epp_cmd+="${run_args}"
  fi
  (cd "${result_dir}" && timeout "${timeout_s}" bash -lc "${epp_cmd}" >"${result_dir}/epp_run.log" 2>&1) || true

  local found_profile=""
  found_profile="$(discover_profile_file "${result_dir}" "${benchmark}" || true)"
  if [[ -n "${found_profile}" ]]; then
    epp_profile="${found_profile}"
  fi

  if [[ ! -f "${epp_paths}" ]]; then
    "${LLVM_EPP}" \
      --round-id 1 \
      --round-mode "${round1_mode}" \
      --round-budget "${PROGRESSIVE_BUDGET}" \
      --incremental-state "${progressive_state}" \
      -p="${epp_profile}" "${bc_file}" > "${epp_paths}" 2>&1 || true
  fi

  # Stage 4: bolt official
  "${LLVM_BOLT}" "${base_bin}" --instrument --instrumentation-file="${bolt_fdata}" "${bolt_runtime_args[@]}" -o "${bolt_instr}" >"${result_dir}/bolt_instrument.log" 2>&1
  if [[ ! -f "${bolt_instr}" ]]; then
    echo "WARN: bolt instrumentation binary missing for ${benchmark}" >&2
    echo "${benchmark},bolt-instrument-failed,0,0,0,0,0,0,0,0,0,${result_dir}" >> "${SUMMARY_CSV}"
    return
  fi

  local bolt_cmd
  bolt_cmd="$(printf '%q ' "${bolt_instr}")"
  if [[ -n "${run_args}" ]]; then
    bolt_cmd+="${run_args}"
  fi
  (cd "${result_dir}" && timeout "${timeout_s}" bash -lc "${bolt_cmd}" >"${result_dir}/bolt_run.log" 2>&1) || true

  if [[ ! -f "${bolt_fdata}" ]]; then
    echo "WARN: bolt profile data missing for ${benchmark}" >&2
    echo "${benchmark},missing-bolt-fdata,0,0,0,0,0,0,0,0,0,${result_dir}" >> "${SUMMARY_CSV}"
    return
  fi

  "${LLVM_BOLT}" "${base_bin}" -o "${bolt_opt}" -data "${bolt_fdata}" -reorder-blocks=ext-tsp >"${result_dir}/bolt_optimize.log" 2>&1
  if [[ ! -f "${bolt_opt}" ]]; then
    echo "WARN: bolt optimize failed for ${benchmark}" >&2
    echo "${benchmark},bolt-optimize-failed,0,0,0,0,0,0,0,0,0,${result_dir}" >> "${SUMMARY_CSV}"
    return
  fi

  # Stage 5: epp -> bolt
  if [[ -f "${epp_profile}" ]] && [[ -f "${epp_paths}" ]]; then
    if python3 "${EPP2BOLT_PY}" \
      --profile "${epp_profile}" \
      --decoded "${epp_paths}" \
      --binary "${base_bin}" \
      --out-preagg "${epp_preagg}" \
      --out-fdata "${epp_fdata}" \
      --objdump "${OBJDUMP_BIN}" \
      --perf2bolt "${PERF2BOLT}" \
      >"${result_dir}/epp2bolt.log" 2>&1; then
      :
    else
      epp_fdata=""
    fi
  else
    epp_fdata=""
  fi

  if [[ -z "${epp_fdata}" ]] || [[ ! -f "${epp_fdata}" ]]; then
    epp_fdata="${bolt_fdata}"
  fi

  # Stage 6: fuse
  python3 "${ROOT_DIR}/scripts/tools/fuse_bolt_epp.py" \
    --bolt-fdata "${bolt_fdata}" \
    --epp-fdata "${epp_fdata}" \
    --out-fdata "${fused_fdata}" \
    --out-path-aware "${path_aware_file}" \
    >"${result_dir}/fusion.log" 2>&1 || cp "${bolt_fdata}" "${fused_fdata}"

  if [[ "${PROGRESSIVE_ENABLE}" == "1" ]] && [[ "${PROGRESSIVE_ROUNDS}" -gt 1 ]]; then
    local round
    local round_sidecars=()
    local round_epp_fdata
    local round_preagg
    local round_profile
    local round_paths
    local round_sidecar
    local round_fused

    if [[ -f "${path_aware_file}" ]]; then
      round_sidecars+=("${path_aware_file}")
    fi

    for round in $(seq 2 "${PROGRESSIVE_ROUNDS}"); do
      local epp_round_log="${result_dir}/epp_run_round${round}.log"
      (cd "${result_dir}" && timeout "${timeout_s}" bash -lc "${epp_cmd}" >"${epp_round_log}" 2>&1) || true

      round_profile="$(discover_profile_file "${result_dir}" "${benchmark}" || true)"
      if [[ -z "${round_profile}" ]]; then
        continue
      fi

      local round_profile_copy="${result_dir}/${benchmark}.round${round}.profile"
      cp "${round_profile}" "${round_profile_copy}" 2>/dev/null || true
      if [[ -f "${round_profile_copy}" ]]; then
        round_profile="${round_profile_copy}"
      fi

      round_preagg="${result_dir}/${benchmark}.round${round}.epp.preagg.txt"
      round_epp_fdata="${result_dir}/${benchmark}.round${round}.epp.fdata"
      round_paths="${result_dir}/${benchmark}.round${round}_paths.txt"
      round_sidecar="${result_dir}/${benchmark}.round${round}.path_aware.tsv"
      round_fused="${result_dir}/${benchmark}.round${round}.fused.fdata"

      local round_mode="collect"
      if [[ "${round}" -eq "${PROGRESSIVE_ROUNDS}" ]]; then
        round_mode="finalize"
      fi

      "${LLVM_EPP}" \
        --round-id "${round}" \
        --round-mode "${round_mode}" \
        --round-budget "${PROGRESSIVE_BUDGET}" \
        --incremental-state "${progressive_state}" \
        -p="${round_profile}" "${bc_file}" >"${round_paths}" 2>&1 || cp "${epp_paths}" "${round_paths}"

      if python3 "${EPP2BOLT_PY}" \
        --profile "${round_profile}" \
        --decoded "${round_paths}" \
        --binary "${base_bin}" \
        --out-preagg "${round_preagg}" \
        --out-fdata "${round_epp_fdata}" \
        --objdump "${OBJDUMP_BIN}" \
        --perf2bolt "${PERF2BOLT}" \
        >"${result_dir}/epp2bolt_round${round}.log" 2>&1; then
        :
      else
        round_epp_fdata="${bolt_fdata}"
      fi

      python3 "${ROOT_DIR}/scripts/tools/fuse_bolt_epp.py" \
        --bolt-fdata "${bolt_fdata}" \
        --epp-fdata "${round_epp_fdata}" \
        --out-fdata "${round_fused}" \
        --out-path-aware "${round_sidecar}" \
        >"${result_dir}/fusion_round${round}.log" 2>&1 || cp "${bolt_fdata}" "${round_fused}"

      if [[ -f "${round_sidecar}" ]]; then
        round_sidecars+=("${round_sidecar}")
      fi
    done

    if [[ ${#round_sidecars[@]} -gt 1 ]] && [[ -f "${MERGE_SIDECARS_PY}" ]]; then
      python3 "${MERGE_SIDECARS_PY}" \
        --output "${progressive_sidecar}" \
        --policy "${PROGRESSIVE_MERGE_POLICY}" \
        --inputs "${round_sidecars[@]}" \
        >"${result_dir}/merge_progressive.log" 2>&1 || true

      if [[ -f "${progressive_sidecar}" ]]; then
        path_aware_file="${progressive_sidecar}"
      fi
    fi
  fi

  # Stage 7: fused optimize
  local path_args=()
  if [[ "${PATH_AWARE_ENABLE}" == "1" ]] && [[ -f "${path_aware_file}" ]] && "${LLVM_BOLT}" --help 2>&1 | grep -q -- '--path-aware-file'; then
    path_args=(
      --path-aware-file="${path_aware_file}"
      --path-aware-alpha="${PATH_AWARE_ALPHA}"
      --path-aware-max-boost="${PATH_AWARE_MAX_BOOST}"
    )
  fi

  "${LLVM_BOLT}" "${base_bin}" -o "${fused_opt}" -data "${fused_fdata}" -reorder-blocks=ext-tsp "${path_args[@]}" >"${result_dir}/fused_bolt_optimize.log" 2>&1
  "${LLVM_BOLT}" "${base_bin}" -o "${epp_opt}" -data "${epp_fdata}" -reorder-blocks=ext-tsp >"${result_dir}/epp_bolt_optimize.log" 2>&1

  if [[ ! -f "${fused_opt}" ]] || [[ ! -f "${epp_opt}" ]]; then
    echo "WARN: fused/epp optimize failed for ${benchmark}" >&2
    echo "${benchmark},fused-or-epp-opt-failed,0,0,0,0,0,0,0,0,0,${result_dir}" >> "${SUMMARY_CSV}"
    return
  fi

  # Stage 8: perf compare
  local base_t bolt_t fused_t epp_t
  base_t=$(measure_perf "${base_bin}" "${run_args}" "${result_dir}" "${PERF_RUNS}" "${perf_timeout_s}s")
  bolt_t=$(measure_perf "${bolt_opt}" "${run_args}" "${result_dir}" "${PERF_RUNS}" "${perf_timeout_s}s")
  fused_t=$(measure_perf "${fused_opt}" "${run_args}" "${result_dir}" "${PERF_RUNS}" "${perf_timeout_s}s")
  epp_t=$(measure_perf "${epp_opt}" "${run_args}" "${result_dir}" "${PERF_RUNS}" "${perf_timeout_s}s")

  local fused_vs_bolt bolt_imp fused_imp epp_imp pa_rows
  fused_vs_bolt=$(awk -v b="${bolt_t}" -v f="${fused_t}" 'BEGIN {if (b>0) printf "%.2f", (b-f)/b*100; else print "0.00"}')
  bolt_imp=$(awk -v b="${base_t}" -v x="${bolt_t}" 'BEGIN {if (b>0) printf "%.2f", (b-x)/b*100; else print "0.00"}')
  fused_imp=$(awk -v b="${base_t}" -v x="${fused_t}" 'BEGIN {if (b>0) printf "%.2f", (b-x)/b*100; else print "0.00"}')
  epp_imp=$(awk -v b="${base_t}" -v x="${epp_t}" 'BEGIN {if (b>0) printf "%.2f", (b-x)/b*100; else print "0.00"}')

  pa_rows="0"
  if [[ -f "${path_aware_file}" ]]; then
    pa_rows=$(grep -vc '^#' "${path_aware_file}" 2>/dev/null || echo "0")
  fi

  echo "${benchmark},ok,${base_t},${bolt_t},${fused_t},${epp_t},${fused_vs_bolt},${bolt_imp},${fused_imp},${epp_imp},${pa_rows},${result_dir}" >> "${SUMMARY_CSV}"

  echo "${benchmark}: base=${base_t}s bolt=${bolt_t}s fused=${fused_t}s epp=${epp_t}s fused_vs_bolt=${fused_vs_bolt}%"

  rm -rf "${tmp_bc_dir}"
}

collect_benchmarks() {
  local -n out_ref=$1

  out_ref=()
  if [[ -n "${BENCHMARKS_INLINE}" ]]; then
    IFS=',' read -r -a out_ref <<< "${BENCHMARKS_INLINE}"
  else
    while IFS= read -r ln; do
      [[ -z "${ln}" ]] && continue
      [[ "${ln}" =~ ^[[:space:]]*# ]] && continue
      out_ref+=("${ln}")
    done < "${BENCH_LIST_FILE}"
  fi
}

print_config() {
  cat <<EOF
===========================================
PathAware Suite Runner
===========================================
Profile mode:  ${PROFILE_MODE}
alpha:         ${PATH_AWARE_ALPHA}
max_boost:     ${PATH_AWARE_MAX_BOOST}
perf runs:     ${PERF_RUNS}
progressive:   ${PROGRESSIVE_ENABLE}
prog rounds:   ${PROGRESSIVE_ROUNDS}
prog mode:     ${PROGRESSIVE_MODE}
prog budget:   ${PROGRESSIVE_BUDGET}
prog policy:   ${PROGRESSIVE_MERGE_POLICY}
benchmark list:${BENCH_LIST_FILE}
LLVM_BOLT:     ${LLVM_BOLT}
PERF2BOLT:     ${PERF2BOLT}
BOLT_RT_LIB:   ${BOLT_RT_LIB:-auto-none}
run dir:       ${RUN_DIR}
===========================================
EOF
}

benchmarks=()
collect_benchmarks benchmarks
print_config

if [[ ${#benchmarks[@]} -eq 0 ]]; then
  echo "ERROR: no benchmark entries found" >&2
  exit 1
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "DRY-RUN benchmark entries:"
  printf '%s\n' "${benchmarks[@]}"
  exit 0
fi

entry_split_ok() {
  local entry="$1"
  IFS='|' read -r suite_rel benchmark timeout_s <<< "${entry}"
  [[ -n "${suite_rel}" && -n "${benchmark}" && -n "${timeout_s}" ]]
}

for entry in "${benchmarks[@]}"; do
  if ! entry_split_ok "${entry}"; then
    echo "WARN: invalid entry format (need suite|benchmark|timeout): ${entry}" >&2
    continue
  fi
  IFS='|' read -r suite_rel benchmark timeout_s <<< "${entry}"
  run_one_benchmark "${suite_rel}" "${benchmark}" "${timeout_s}"
done

echo ""
echo "Done. Summary: ${SUMMARY_CSV}"
if [[ -f "${SUMMARY_CSV}" ]]; then
  cat "${SUMMARY_CSV}"
fi

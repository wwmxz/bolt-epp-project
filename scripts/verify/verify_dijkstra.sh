#!/usr/bin/env bash
set -uo pipefail

#############################################################################
# EPP+BOLT Verification with MultiSource Dijkstra (Routing Algorithm)
# Purpose: Verify EPP+BOLT optimization on complex branching workload
# Target: network-dijkstra - shortest path algorithm with high branch complexity
# Time: ~5-8 minutes total
#############################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULT_DIR="${ROOT_DIR}/results/verify_dijkstra"
TS_BUILD_DIR="${ROOT_DIR}/build-ts-multisource"

CLANG="${CLANG:-clang}"
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

mkdir -p "${RESULT_DIR}"

BENCHMARK="network-dijkstra"
TS_BIN_DIR="${TS_BUILD_DIR}/MultiSource/Benchmarks/MiBench/network-dijkstra"
TS_SRC_DIR="${ROOT_DIR}/llvm-test-suite/MultiSource/Benchmarks/MiBench/network-dijkstra"
TS_BIN="${TS_BIN_DIR}/${BENCHMARK}"

if [[ ! -f "${TS_BIN}" ]]; then
  echo "ERROR: Dijkstra binary not found at ${TS_BIN}" >&2
  echo "       First run: scripts/prepare_multisource_classics.sh" >&2
  exit 1
fi

echo "==========================================="
echo "EPP+BOLT Verification: ${BENCHMARK}"
echo "==========================================="
echo
echo "Toolchain:"
echo "  LLVM_BOLT: ${LLVM_BOLT}"
echo "  PERF2BOLT: ${PERF2BOLT}"
echo

# ─────────────────────────────────────────────────────────────────────────
# Stage 1: Copy & Recompile Baseline Binary
# ─────────────────────────────────────────────────────────────────────────
BASE_BIN="${RESULT_DIR}/dijkstra_base"
echo "[1/7] Compiling baseline binary..."

# Get source files from the Dijkstra directory
mapfile -t SRC_FILES < <(find "${TS_SRC_DIR}" -maxdepth 1 \( -name '*.c' -o -name '*.cc' \) | sort)

if [[ ${#SRC_FILES[@]} -eq 0 ]]; then
  echo "ERROR: No source files found in ${TS_SRC_DIR}" >&2
  exit 1
fi

# Extract compile flags from CMakeLists.txt
CMAKE_FILE="${TS_SRC_DIR}/CMakeLists.txt"
CPPFLAGS_STR=""
CFLAGS_STR=""
LDFLAGS_STR=""
RUN_ARGS=""

if [[ -f "${CMAKE_FILE}" ]]; then
  # Extract CPPFLAGS
  CPPFLAGS_STR=$(grep -E "list\(APPEND CPPFLAGS" "${CMAKE_FILE}" | sed -E "s/^[[:space:]]*list\(APPEND CPPFLAGS[[:space:]]+//; s/[[:space:]]*\)[[:space:]]*$//" 2>/dev/null || true)
  # Extract CFLAGS
  CFLAGS_STR=$(grep -E "list\(APPEND CFLAGS" "${CMAKE_FILE}" | sed -E "s/^[[:space:]]*list\(APPEND CFLAGS[[:space:]]+//; s/[[:space:]]*\)[[:space:]]*$//" 2>/dev/null || true)
  # Extract LDFLAGS
  LDFLAGS_STR=$(grep -E "list\(APPEND LDFLAGS" "${CMAKE_FILE}" | sed -E "s/^[[:space:]]*list\(APPEND LDFLAGS[[:space:]]+//; s/[[:space:]]*\)[[:space:]]*$//" 2>/dev/null || true)
  # Extract RUN_OPTIONS
  RUN_ARGS=$(grep -E "set\(RUN_OPTIONS" "${CMAKE_FILE}" | sed -E "s/^[[:space:]]*set\(RUN_OPTIONS[[:space:]]+//; s/[[:space:]]*\)[[:space:]]*$//" 2>/dev/null | head -1 || true)
fi

# Compile baseline with extracted flags
"${CLANG}" -O2 -g ${CPPFLAGS_STR} ${CFLAGS_STR} "${SRC_FILES[@]}" -o "${BASE_BIN}" ${LDFLAGS_STR} -Wl,--emit-relocs \
  >"${RESULT_DIR}/compile_base.log" 2>&1

if [[ ! -f "${BASE_BIN}" ]]; then
  echo "ERROR: Baseline compilation failed" >&2
  cat "${RESULT_DIR}/compile_base.log" >&2
  exit 1
fi

echo "      ? Baseline: ${BASE_BIN}"
echo

# ─────────────────────────────────────────────────────────────────────────
# Stage 2: Build LLVM Bitcode for EPP
# ─────────────────────────────────────────────────────────────────────────
echo "[2/7] Building LLVM bitcode for EPP..."

BC_FILE="${RESULT_DIR}/${BENCHMARK}.bc"
TMP_BC_DIR="${RESULT_DIR}/.bc_temp"
rm -rf "${TMP_BC_DIR}"
mkdir -p "${TMP_BC_DIR}"

BC_FILES=()
for src in "${SRC_FILES[@]}"; do
  bname="$(basename "${src}")"
  bc_out="${TMP_BC_DIR}/${bname%.*}.bc"
  "${CLANG}" -g -emit-llvm -c ${CPPFLAGS_STR} ${CFLAGS_STR} "${src}" -o "${bc_out}" \
    >"${RESULT_DIR}/compile_bc_${bname}.log" 2>&1
  BC_FILES+=("${bc_out}")
done

if [[ ${#BC_FILES[@]} -gt 1 ]]; then
  "${LLVM_LINK}" "${BC_FILES[@]}" -o "${BC_FILE}" \
    >"${RESULT_DIR}/link_bc.log" 2>&1
else
  cp "${BC_FILES[0]}" "${BC_FILE}"
fi

echo "      ? Bitcode: ${BC_FILE}"
echo

# ─────────────────────────────────────────────────────────────────────────
# Stage 3: EPP Profile Collection
# ─────────────────────────────────────────────────────────────────────────
echo "[3/7] Collecting EPP path profiles..."

EPP_PROFILE="${RESULT_DIR}/${BENCHMARK}.profile"
EPP_BC="${RESULT_DIR}/${BENCHMARK}.epp.bc"
EPP_EXE="${RESULT_DIR}/${BENCHMARK}_epp_exe"

"${LLVM_EPP}" "${BC_FILE}" -o "${EPP_PROFILE}" \
  >"${RESULT_DIR}/epp_instrument.log" 2>&1

if [[ -f "${BC_FILE%.bc}.epp.bc" ]]; then
  EPP_BC="${BC_FILE%.bc}.epp.bc"
fi

"${CLANG}" "${EPP_BC}" -o "${EPP_EXE}" -lepp-rt ${LDFLAGS_STR} \
  >"${RESULT_DIR}/epp_link.log" 2>&1

echo "      ? EPP executable created"

# For input file, copy it to result directory if needed
if [[ -n "${RUN_ARGS}" ]] && [[ "${RUN_ARGS}" == *"input"* ]]; then
  if [[ -f "${TS_SRC_DIR}/${RUN_ARGS}" ]]; then
    cp "${TS_SRC_DIR}/${RUN_ARGS}" "${RESULT_DIR}/"
  fi
fi

# Run EPP executable in results directory (with timeout)
echo "      Running EPP with input: ${RUN_ARGS}"
cd "${RESULT_DIR}"
timeout 120s "${EPP_EXE}" ${RUN_ARGS} >"${RESULT_DIR}/epp_run.log" 2>&1 || true
cd - >/dev/null

# Find the generated profile file
FOUND_PROFILE=""
for pfile in "${RESULT_DIR}"/*.profile "${RESULT_DIR}"/*profile* "${RESULT_DIR}"/network-dijkstra* "${RESULT_DIR}"/default.profile "${PWD}"/*.profile; do
  if [[ -f "${pfile}" ]] 2>/dev/null && file "${pfile}" 2>/dev/null | grep -q "ASCII text"; then
    FOUND_PROFILE="${pfile}"
    break
  fi
done

if [[ -z "${FOUND_PROFILE}" ]]; then
  echo "      ? No EPP profile file found, checking for alternatives..." >&2
  ls -la "${RESULT_DIR}"/ | grep -E '\.(profile|log|txt)' >&2 || true
  echo "      ? Using decoded paths file if available"
else
  EPP_PROFILE="${FOUND_PROFILE}"
  echo "      ? Found EPP profile: $(basename ${EPP_PROFILE})"
fi

# Decode EPP paths
EPP_PATHS="${RESULT_DIR}/${BENCHMARK}_paths.txt"
if [[ ! -f "${EPP_PATHS}" ]]; then
  "${LLVM_EPP}" -p="${EPP_PROFILE}" "${BC_FILE}" > "${EPP_PATHS}" 2>&1
else
  echo "      ? Decoded paths already available"
fi

echo "      ? EPP profiles collected"
echo

# ─────────────────────────────────────────────────────────────────────────
# Stage 4: BOLT Official Optimization
# ─────────────────────────────────────────────────────────────────────────
echo "[4/7] BOLT Official optimization..."

BOLT_INSTR="${RESULT_DIR}/dijkstra_bolt_instr"
BOLT_FDATA="${RESULT_DIR}/dijkstra.bolt.fdata"
BOLT_OPT="${RESULT_DIR}/dijkstra_bolt_opt"

"${LLVM_BOLT}" "${BASE_BIN}" \
  --instrument \
  --instrumentation-file="${BOLT_FDATA}" \
  -o "${BOLT_INSTR}" \
  >"${RESULT_DIR}/bolt_instrument.log" 2>&1

echo "      ? BOLT instrumented binary created"

# Run instrumented binary with input file
cd "${RESULT_DIR}"
timeout 120s "${BOLT_INSTR}" ${RUN_ARGS} >"${RESULT_DIR}/bolt_run.log" 2>&1 || true
cd - >/dev/null

# Optimize with BOLT profiles
"${LLVM_BOLT}" "${BASE_BIN}" \
  -o "${BOLT_OPT}" \
  -data "${BOLT_FDATA}" \
  -reorder-blocks=ext-tsp \
  >"${RESULT_DIR}/bolt_optimize.log" 2>&1

echo "      ? BOLT-optimized binary: ${BOLT_OPT}"
echo

# ─────────────────────────────────────────────────────────────────────────
# Stage 5: EPP→BOLT Data Conversion (Optional - try EPP if available)
# ─────────────────────────────────────────────────────────────────────────
echo "[5/7] Converting EPP profiles to BOLT format..."

EPP_PREAGG="${RESULT_DIR}/dijkstra.epp.preagg.txt"
EPP_FDATA="${RESULT_DIR}/dijkstra.epp.fdata"

# Check if we have valid EPP data
if [[ -f "${EPP_PROFILE}" ]] && [[ "${EPP_PROFILE}" != "${EPP_PATHS}" ]]; then
  # Try to convert EPP profile
  if python3 "${EPP2BOLT_PY}" \
    --profile "${EPP_PROFILE}" \
    --decoded "${EPP_PATHS}" \
    --binary "${BASE_BIN}" \
    --out-preagg "${EPP_PREAGG}" \
    --out-fdata "${EPP_FDATA}" \
    --objdump llvm-objdump \
    --perf2bolt "${PERF2BOLT}" \
    >"${RESULT_DIR}/epp2bolt.log" 2>&1; then
    echo "      ? EPP fdata: ${EPP_FDATA}"
  else
    echo "      ? EPP conversion failed, will use BOLT data only"
    EPP_FDATA=""
  fi
else
  echo "      ? No EPP profile data, will use BOLT data only"
  EPP_FDATA=""
fi

if [[ -z "${EPP_FDATA}" ]] || [[ ! -f "${EPP_FDATA}" ]]; then
  echo "      Creating EPP+BOLT optimization from BOLT data..."
  EPP_FDATA="${BOLT_FDATA}"
fi

echo

# ─────────────────────────────────────────────────────────────────────────
# Stage 6: BOLT+EPP Data Fusion (新策略：合并两种数据以获得完整信息)
# ─────────────────────────────────────────────────────────────────────────
echo "[6/8] Fusing BOLT and EPP data..."

FUSED_FDATA="${RESULT_DIR}/dijkstra.fused.fdata"
PATH_AWARE_FILE="${RESULT_DIR}/dijkstra.path_aware.tsv"

# 只有当两个 fdata 文件都存在时才执行融合
if [[ -f "${BOLT_FDATA}" ]] && [[ -f "${EPP_FDATA}" ]]; then
  python3 "${ROOT_DIR}/scripts/tools/fuse_bolt_epp.py" \
    --bolt-fdata "${BOLT_FDATA}" \
    --epp-fdata "${EPP_FDATA}" \
    --out-fdata "${FUSED_FDATA}" \
    --out-path-aware "${PATH_AWARE_FILE}" \
    >"${RESULT_DIR}/fusion.log" 2>&1
  
  echo "      ? Data fusion complete: ${FUSED_FDATA}"
  if [[ -f "${PATH_AWARE_FILE}" ]]; then
    echo "      ? Path-aware sidecar: ${PATH_AWARE_FILE}"
  fi
else
  echo "      ? Missing data files for fusion, skipping..."
  FUSED_FDATA="${BOLT_FDATA}"
  PATH_AWARE_FILE=""
fi
echo

# ─────────────────────────────────────────────────────────────────────────
# Stage 7: BOLT Optimization with Fused Data
# ─────────────────────────────────────────────────────────────────────────
echo "[7/8] BOLT optimization with fused data..."

FUSED_BOLT_OPT="${RESULT_DIR}/dijkstra_fused_bolt_opt"
PATH_AWARE_ENABLE="${PATH_AWARE_ENABLE:-1}"
PATH_AWARE_ALPHA="${PATH_AWARE_ALPHA:-0.25}"
PATH_AWARE_MAX_BOOST="${PATH_AWARE_MAX_BOOST:-8}"
PATH_AWARE_ARGS=()
if [[ "${PATH_AWARE_ENABLE}" == "1" ]] && [[ -n "${PATH_AWARE_FILE}" ]] && [[ -f "${PATH_AWARE_FILE}" ]] && "${LLVM_BOLT}" --help 2>&1 | grep -q -- '--path-aware-file'; then
  PATH_AWARE_ARGS=(
    --path-aware-file="${PATH_AWARE_FILE}"
    --path-aware-alpha="${PATH_AWARE_ALPHA}"
    --path-aware-max-boost="${PATH_AWARE_MAX_BOOST}"
  )
  echo "      ? Path-aware ext-tsp enabled (alpha=${PATH_AWARE_ALPHA}, max_boost=${PATH_AWARE_MAX_BOOST})"
elif [[ -n "${PATH_AWARE_FILE}" ]] && [[ -f "${PATH_AWARE_FILE}" ]]; then
  if [[ "${PATH_AWARE_ENABLE}" != "1" ]]; then
    echo "      ? Path-aware disabled by PATH_AWARE_ENABLE=${PATH_AWARE_ENABLE}; using plain ext-tsp"
  else
    echo "      ? Path-aware sidecar exists, but current llvm-bolt does not support --path-aware-file"
    echo "      ? Falling back to plain ext-tsp"
  fi
fi

"${LLVM_BOLT}" "${BASE_BIN}" \
  -o "${FUSED_BOLT_OPT}" \
  -data "${FUSED_FDATA}" \
  -reorder-blocks=ext-tsp \
  "${PATH_AWARE_ARGS[@]}" \
  >"${RESULT_DIR}/fused_bolt_optimize.log" 2>&1

echo "      ? FUSED+BOLT-optimized: ${FUSED_BOLT_OPT}"
echo

# ─────────────────────────────────────────────────────────────────────────
# Stage 8: EPP-only Optimization (用于对比)
# ─────────────────────────────────────────────────────────────────────────
echo "[8/9] EPP-only optimization (for comparison)..."

EPP_BOLT_OPT="${RESULT_DIR}/dijkstra_epp_bolt_opt"

"${LLVM_BOLT}" "${BASE_BIN}" \
  -o "${EPP_BOLT_OPT}" \
  -data "${EPP_FDATA}" \
  -reorder-blocks=ext-tsp \
  >"${RESULT_DIR}/epp_bolt_optimize.log" 2>&1

echo "      ? EPP-only-optimized: ${EPP_BOLT_OPT}"
echo

# ─────────────────────────────────────────────────────────────────────────
# Stage 9: Summary Report
# ─────────────────────────────────────────────────────────────────────────
echo "[9/9] Summary Report"
echo "==========================================="

# Binary sizes
BASE_SIZE=$(stat -c%s "${BASE_BIN}")
BOLT_SIZE=$(stat -c%s "${BOLT_OPT}")
FUSED_SIZE=$(stat -c%s "${FUSED_BOLT_OPT}") 
EPP_SIZE=$(stat -c%s "${EPP_BOLT_OPT}")

echo "Binary Sizes:"
echo "  Baseline:           $(numfmt --to=iec ${BASE_SIZE} 2>/dev/null || echo ${BASE_SIZE} bytes)"
echo "  BOLT-opt:           $(numfmt --to=iec ${BOLT_SIZE} 2>/dev/null || echo ${BOLT_SIZE} bytes)"
echo "  FUSED+BOLT-opt:     $(numfmt --to=iec ${FUSED_SIZE} 2>/dev/null || echo ${FUSED_SIZE} bytes)"
echo "  EPP-only-opt:       $(numfmt --to=iec ${EPP_SIZE} 2>/dev/null || echo ${EPP_SIZE} bytes)"
echo

# Profile statistics
BOLT_LINES=$(wc -l < "${BOLT_FDATA}" 2>/dev/null || echo "0")
EPP_LINES=$(wc -l < "${EPP_FDATA}" 2>/dev/null || echo "0")
FUSED_LINES=$(wc -l < "${FUSED_FDATA}" 2>/dev/null || echo "0")
PATH_AWARE_LINES="0"
if [[ -n "${PATH_AWARE_FILE}" ]] && [[ -f "${PATH_AWARE_FILE}" ]]; then
  PATH_AWARE_LINES=$(grep -vc '^#' "${PATH_AWARE_FILE}" 2>/dev/null || echo "0")
fi

echo "Profile Coverage (fdata entries):"
echo "  BOLT only:          ${BOLT_LINES} entries"
echo "  EPP only:           ${EPP_LINES} entries"
echo "  FUSED (BOLT+EPP):   ${FUSED_LINES} entries"
echo "  Path-aware edges:   ${PATH_AWARE_LINES} entries"
if [[ ${BOLT_LINES} -gt 0 ]]; then
  DELTA=$(echo "scale=1; (${FUSED_LINES} - ${BOLT_LINES}) / ${BOLT_LINES} * 100" | bc 2>/dev/null || echo "N/A")
  echo "  Fusion delta:       ${DELTA}%"
fi
echo

echo "Binaries ready for performance testing:"
echo "  1. Baseline:        ${BASE_BIN}"
echo "  2. BOLT-opt:        ${BOLT_OPT}"
echo "  3. FUSED+BOLT-opt:  ${FUSED_BOLT_OPT}  <- new strategy"
echo "  4. EPP-only-opt:    ${EPP_BOLT_OPT}    <- old strategy"
echo
echo "Next: Run ./perf_verify_dijkstra_fused.sh to compare performance"
echo "==========================================="

rm -rf "${TMP_BC_DIR}"

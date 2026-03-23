#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS_SRC_DIR="${ROOT_DIR}/llvm-test-suite"
BUILD_DIR="${ROOT_DIR}/build-ts-multisource"
TARGET_FILE="${ROOT_DIR}/scripts/multisource_classics_targets.txt"
MANIFEST_DIR="${ROOT_DIR}/results"
MANIFEST_FILE="${MANIFEST_DIR}/multisource_classics_manifest.tsv"

C_COMPILER="${C_COMPILER:-clang}"
CXX_COMPILER="${CXX_COMPILER:-clang++}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
GENERATOR="${GENERATOR:-Ninja}"

if [[ ! -d "${TS_SRC_DIR}" ]]; then
  echo "error: llvm-test-suite not found at ${TS_SRC_DIR}" >&2
  exit 1
fi

if [[ ! -f "${TARGET_FILE}" ]]; then
  echo "error: target list not found at ${TARGET_FILE}" >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake not found in PATH" >&2
  exit 1
fi

if [[ "${GENERATOR}" == "Ninja" ]] && ! command -v ninja >/dev/null 2>&1; then
  echo "warning: ninja not found, fallback to Unix Makefiles"
  GENERATOR="Unix Makefiles"
fi

mkdir -p "${MANIFEST_DIR}"
mkdir -p "${BUILD_DIR}"

echo "[1/4] Configure llvm-test-suite (MultiSource only)"
cmake -S "${TS_SRC_DIR}" -B "${BUILD_DIR}" \
  -G "${GENERATOR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="${C_COMPILER}" \
  -DCMAKE_CXX_COMPILER="${CXX_COMPILER}" \
  -DTEST_SUITE_SUBDIRS=MultiSource \
  -DTEST_SUITE_RUN_BENCHMARKS=OFF \
  -DTEST_SUITE_COLLECT_CODE_SIZE=OFF \
  -DTEST_SUITE_COLLECT_COMPILE_TIME=OFF

echo "[2/4] Resolve selected targets"
mapfile -t requested_targets < <(grep -vE '^\s*#|^\s*$' "${TARGET_FILE}")
if [[ ${#requested_targets[@]} -eq 0 ]]; then
  echo "error: no targets found in ${TARGET_FILE}" >&2
  exit 1
fi

mapfile -t available_targets < <(
  grep -RhoE 'llvm_multisource\([^[:space:]\)]+' "${TS_SRC_DIR}/MultiSource/Benchmarks" \
  | sed -E 's/^llvm_multisource\(//' \
  | sort -u
)

declare -A target_exists=()
for t in "${available_targets[@]}"; do
  target_exists["${t}"]=1
done

build_targets=()
missing_targets=()
for t in "${requested_targets[@]}"; do
  if [[ -n "${target_exists[${t}]:-}" ]]; then
    build_targets+=("${t}")
  else
    missing_targets+=("${t}")
  fi
done

if [[ ${#build_targets[@]} -eq 0 ]]; then
  echo "error: none of the selected targets are available in this build" >&2
  echo "hint: check target names in ${TARGET_FILE}" >&2
  exit 1
fi

echo "Targets to build (${#build_targets[@]}): ${build_targets[*]}"
if [[ ${#missing_targets[@]} -gt 0 ]]; then
  echo "Skipped missing targets (${#missing_targets[@]}): ${missing_targets[*]}"
fi

echo "[3/4] Build selected targets"
cmake --build "${BUILD_DIR}" -j "${BUILD_JOBS}" --target "${build_targets[@]}"

echo "[4/4] Generate executable manifest"
{
  echo -e "Target\tBinaryPath"
  for t in "${build_targets[@]}"; do
    # Typical llvm-test-suite binary path pattern under MultiSource.
    bin_path="$(find "${BUILD_DIR}/MultiSource/Benchmarks" -type f -name "${t}" -perm -111 2>/dev/null | head -n 1 || true)"
    if [[ -n "${bin_path}" ]]; then
      echo -e "${t}\t${bin_path}"
    else
      echo -e "${t}\t<not-found-after-build>"
    fi
  done
} > "${MANIFEST_FILE}"

echo "Ready: ${MANIFEST_FILE}"

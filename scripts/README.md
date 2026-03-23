# Scripts Layout

`bolt-epp-test` scripts are organized by module to reduce root-level clutter.

## Module Folders

- `prepare/`: benchmark and environment preparation
- `verify/`: single-benchmark verification pipelines
- `perf/`: performance comparison and statistics
- `suite/`: multi-benchmark suite runners
- `multiround/`: multi-round collection and merge validation
- `tools/`: Python helpers for conversion and fusion

## Current Entrypoints

- `prepare_multisource_classics.sh`
- `verify/verify_dijkstra.sh`
- `perf/perf_verify_dijkstra.sh`
- `perf/perf_verify_dijkstra_fused.sh`
- `perf/perf_verify_tsp.sh`
- `perf/perf_test.sh`
- `perf/perf_multisource.sh`
- `suite/run_pathaware_suite.sh`
- `multiround/multiround_rapid_test.sh`
- `multiround/multiround_quick_validation.sh`
- `multiround/multiround_simple_summary.sh`
- `multiround/run_option_b_full_validation.sh`
- `tools/epp2bolt.py`
- `tools/fuse_bolt_epp.py`

## Compatibility

Root-level wrapper scripts are intentionally retained. Existing commands like
`bash verify_dijkstra.sh` still work and forward to module scripts.

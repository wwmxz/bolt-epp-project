# 模块：多轮采集与合并（Multi-round）

## 作用

评估“多轮采集 + sidecar 合并”是否优于单轮融合。

## 主要文件

- `scripts/multiround/multiround_rapid_test.sh`（模拟版，快速）
- `scripts/multiround/multiround_quick_validation.sh`（三轮快速验证）
- `scripts/multiround/run_option_b_full_validation.sh`（真实版，3 轮完整采集）

## 使用

```bash
# 快速模拟（2 分钟）
bash scripts/multiround/multiround_rapid_test.sh

# 完整验证（3 轮真实采集，30~40 分钟）
bash scripts/multiround/run_option_b_full_validation.sh
```

## 合并策略（当前）

- 对同一 edge key：
  - `fused_count` 取多轮最大值
  - `confidence` 取多轮平均值

## 输出

- `results/multiround_rapid_test/`
- `results/multiround_full_validation/<timestamp>/`
  - `round_1..3/`
  - `dijkstra.multiround.path_aware.tsv`
  - `perf_summary.csv`

## 解读建议

- 重点看 `perf_summary.csv` 中 Multi-Round-Merged 与 Fused-Single 的 delta
- 同时检查 fail rate，避免“更快但不稳定”的假收益

# 模块：套件结果分析（Suite Results Analysis）

## 作用

解释 `run_pathaware_suite` 的结果字段和分析边界，避免将其与单基准 `perf_verify_dijkstra_fused` 混淆。

## 结果来源

- 生产脚本：`scripts/suite/run_pathaware_suite.sh`
- 结果目录：`results/pathaware_suite/<timestamp>_<profile>/`
- 核心文件：`summary.csv`

## 当前事实边界

- `scripts/perf/perf_verify_dijkstra_fused.sh` 仅针对 `verify_dijkstra` 的单基准结果，不分析 suite。
- suite 的跨 benchmark 统计目前由 `run_pathaware_suite.sh` 直接写入 `summary.csv`。
- 当前仓库中没有独立的 suite 回归分析脚本（例如 `scripts/perf/perf_verify_suite.sh`）。

## summary.csv 字段说明（按代码行为）

- `benchmark`: 基准名
- `status`: 运行状态（`ok` 或失败原因）
- `base_s/bolt_s/fused_s/epp_s`: 各变体平均耗时
- `fused_vs_bolt_pct`: 融合相对 BOLT 的提升百分比
- `bolt_imp_pct/fused_imp_pct/epp_imp_pct`: 相对 baseline 的提升百分比
- `path_aware_rows`: sidecar 记录数（用于判断 path-aware 覆盖规模）
- `result_dir`: 该 benchmark 对应结果目录

## 推荐分析方式

1. 先过滤 `status != ok`，排除构建或采样失败样本。
2. 用 `fused_vs_bolt_pct` 判断融合策略在各 benchmark 的有效性。
3. 结合 `path_aware_rows` 观察覆盖规模与收益是否一致。
4. 与 profile/testset 维度联合比较（stable/aggressive/custom, simple/large/custom）。

## 后续可扩展（可选）

如需更系统的跨 benchmark 回归分析，建议新增独立脚本：

- 候选路径：`scripts/perf/perf_verify_suite_summary.sh`
- 目标：聚合多个 `summary.csv`，输出 profile/testset 维度的总览报告。

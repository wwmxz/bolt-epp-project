# 模块：结果与回归分析（Results + Regression）

## 作用

统一管理实验结果、基准对比和回归判断。

## 结果目录规范

- 单基准：`results/verify_dijkstra/`, `results/verify_tsp/`
- 套件：`results/pathaware_suite/<timestamp>_<profile>/`
- 多轮：`results/multiround_full_validation/<timestamp>/`

## 关键文件

- `results/verify_dijkstra/performance_comparison_fused.csv`
- `results/pathaware_suite/*/summary.csv`
- `results/multiround_full_validation/*/perf_summary.csv`

## 建议判据

- 单轮对比：Fused-Single 相对 BOLT 是否持续为正
- 多轮对比：Multi-Round-Merged 相对 Fused-Single 是否为正
- 稳定性：stddev 与 fail_rate 不应显著恶化

## 回归处理建议

1. 先确认输入与运行参数是否一致（input.dat, alpha, max_boost）
2. 对可疑 case 增加重复次数（>=30）
3. 保留 raw runs，避免仅看均值

# 项目成果验证与后续规划

更新时间：2026-03-23

## 1. 本次结构规范化完成项

- 新增项目总入口：`README.md`
- 新增架构文档：`docs/ARCHITECTURE.md`
- 新增开发规范：`docs/DEVELOPMENT_CONVENTIONS.md`
- 新增模块说明（介绍+使用）：`docs/modules/*.md`
- 新增路线图：`docs/ROADMAP_PROGRESSIVE_PATH_PROFILE_EXTTSP.md`

这意味着后续代码可以按“Phase + Module”组织，不再依赖口头约定。

## 2. 本次验证结果（当前快照）

### 2.1 单基准融合验证
来源：`results/verify_dijkstra/performance_comparison_fused.csv`

- Baseline: 0.040297s
- BOLT: 0.039261s（+2.57%）
- FUSED+BOLT: 0.039386s（+2.26%）
- EPP-only: 0.040045s（+0.63%）

结论：在这次 10-run 快照中，BOLT 最优，FUSED 正收益但未超过 BOLT。

### 2.2 历史完整多轮验证（Option B）
来源：`results/multiround_full_validation/20260323_133345/perf_summary.csv`

- Baseline: 0.067684s
- BOLT: 0.067452s（+0.34%）
- Fused-Single: 0.067039s（+0.95%）
- Multi-Round-Merged: 0.067344s（+0.50%）

结论：历史完整验证里 Fused-Single 优于 BOLT，多轮合并次之。

### 2.3 套件样本（stable profile）
来源：`results/pathaware_suite/20260323_093924_stable/summary.csv`

- network-dijkstra: fused_vs_bolt = +0.63%
- path_aware_rows = 14

结论：在套件样本里，PathAware 融合有正收益信号。

## 3. 成果总结（截至当前）

已完成：
- PathAware sidecar 端到端链路（生成 -> 消费 -> ext-tsp 重加权）
- 单基准/套件/多轮三类验证框架
- 关键指标统一（mean/stddev/fail rate/improvement）

当前风险：
- 收益稳定性受参数和样本波动影响明显
- 多轮合并策略（max count + avg confidence）尚未稳定优于单轮
- 同一 benchmark 不同批次存在结论反转，需要更系统的统计验证

## 4. 之后规划：渐进式 Path Profile + ExtTsp

目标：把“能跑通”升级为“稳定增益”。

### Phase C-1 参数化采集（EPP）
- 新增 round_id/mode/budget
- 输出分轮 profile

### Phase C-2 增量状态管理
- 记录已覆盖/新增路径与累计权重
- 支持下一轮增量采样

### Phase C-3 多轮融合流水线
- epp2bolt 支持多轮输入
- 输出兼容 fdata + path-aware sidecar

### Phase C-4 策略优化
- Round1 热路径保守
- Round2 热扩展中等激进
- Round3 补盲激进

## 5. 推荐执行顺序（短期）

1. 固化参数矩阵（alpha/max_boost）并对关键基准做 30-run 稳定性测试
2. 将多轮策略由“固定 max/avg”升级为“覆盖优先 + 置信度门限”
3. 引入 round-aware 接口（先在脚本层模拟，再落到 llvm-epp）
4. 在 simple + large testset 上形成统一结论报告

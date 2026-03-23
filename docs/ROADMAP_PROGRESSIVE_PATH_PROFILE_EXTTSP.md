# 规划：渐进式 Path Profile 与 ExtTsp 结合

## 当前状态（截至本次）

- 已完成 PathAware sidecar -> BOLT ext-tsp 的最小可运行链路
- 已具备单轮验证、套件验证、多轮验证编排脚本
- 已有性能结果归档（single/suite/multiround）

## 目标

将 EPP 从单轮采集升级为“渐进式多轮采集”，并让 ExtTsp 在不改 CFG 的前提下利用更高质量路径信息。

## Phase C 分解

### C1: llvm-epp 增加多轮参数

目标参数：
- `round_id`
- `mode`（hot/balance/blind）
- `budget`（本轮采样预算）

验收：
- 可通过命令行切换不同轮配置
- 同一 benchmark 可产出分轮 profile

### C2: 增量状态文件

状态文件建议字段：
- covered_paths
- newly_covered_paths
- cumulative_weights
- round_meta（id/mode/budget）

验收：
- 每轮结束后状态可持久化
- 下一轮可读取并增量更新

### C3: epp2bolt 多轮合并

目标：
- 输入多轮 EPP 数据
- 输出兼容 BOLT fdata + path-aware sidecar

验收：
- 向后兼容单轮输入
- 多轮输出可被现有 verify/suite 脚本消费

### C4: 分轮策略（收益优先）

建议策略：
- Round 1: hot 路径（保守）
- Round 2: hot 扩展（中等激进）
- Round 3: blind 补盲（激进）

验收：
- 在目标 benchmark 上，多轮相对单轮有稳定提升或明确边界结论

## 与 ExtTsp 结合原则

- 只改 edge count，不改 CFG 结构
- 保持 `path-aware-alpha` 与 `max-boost` 的可控上限
- 先保证稳定性，再追求峰值收益

## 建议里程碑

1. M1（接口）: 完成 C1+C2，产出 round-aware profile 与状态文件
2. M2（融合）: 完成 C3，打通 verify_dijkstra 多轮输入
3. M3（策略）: 完成 C4，跑 simple + large testset 出对比报告

## 失败回退策略

- 任一阶段失败时，保留现有单轮路径作为默认路径
- 多轮能力通过新参数显式开启，避免影响已有流程

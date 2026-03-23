# 架构与阶段划分

## 目标

将 BOLT 的边级计数和 EPP 的路径信息融合，生成可用于 ext-tsp 的优化输入，并通过可复现实验评估收益。

## 目录职责（模块化）

- `scripts/`: 构建/准备脚本（基准初始化）
- `testsets/`: 套件运行的测试集定义（simple/large/custom）
- `scripts/verify/verify_*.sh` / `scripts/perf/perf_*.sh`: 单任务验证与性能对比入口
- `scripts/suite/run_*.sh`: 套件编排入口
- `scripts/multiround/*.sh`: 多轮验证入口
- `results/`: 统一结果归档（日志、csv、raw runs、中间产物）
- `docs/`: 规范、模块说明、路线图

## Phase 划分

> 重要：这里的 Phase 是“能力模块”，不是必须按 0->1->2->3->4 串行执行的流水线。
> 除 Phase 0 外，Phase 1/2/3/4 可以按目标组合使用。

### Phase 0: 准备
- 脚本：`scripts/prepare_multisource_classics.sh`
- 产物：`build-ts-multisource/` + manifest
- 关系：其余 Phase 的共同前置条件。

### Phase 1: 单基准验证
- 脚本：`scripts/verify/verify_dijkstra.sh`
- 数据流：源码 -> baseline/bin -> bitcode -> epp profile -> epp fdata -> bolt fdata -> fused fdata -> optimized bins
- 关系：用于功能打通和单点调试；其产物常作为 Phase 4（统计对比）的输入，也可作为 Phase 3 的单轮基线。

### Phase 2: 套件验证
- 脚本：`scripts/suite/run_pathaware_suite.sh`
- 维度：profile（stable/aggressive/custom） + testset（simple/large/custom）
- 关系：是“批量编排模块”，用于多 benchmark 扩展验证。
- 说明：它不是简单等于“Phase 1 + Phase 4”的机械相加；它会复用单基准流程思想，但关注的是跨基准可扩展性与配置维度覆盖。

### Phase 3: 多轮验证
- 快速版：`scripts/multiround/multiround_rapid_test.sh`（模拟）
- 完整版：`scripts/multiround/run_option_b_full_validation.sh`（真实 3 轮）
- 关系：面向“多轮渐进式 EPP/sidecar 合并策略”的预评估与方案验证。
- 说明：这是下一阶段方向的实验模块，不依赖 Phase 2；可在单 benchmark 上独立验证策略收益。

### Phase 4: 回归分析
- 4A 单基准回归（Dijkstra）
	- 脚本：`scripts/perf/perf_verify_dijkstra_fused.sh`
	- 输入：`results/verify_dijkstra/` 下的 4 个二进制（baseline/BOLT/FUSED/EPP-only）
	- 输出：`results/verify_dijkstra/performance_comparison_fused.csv`
	- 指标：均值、方差、fail rate、相对 baseline/BOLT/Fused 的改进率
- 4B 套件结果汇总分析（跨 benchmark）
	- 结果来源：`scripts/suite/run_pathaware_suite.sh` 运行后生成 `results/pathaware_suite/*/summary.csv`
	- 说明：当前代码中没有独立的“suite 回归分析脚本”；分析入口是 suite 运行产出的 summary csv。
	- 指标：每 benchmark 的 base/bolt/fused/epp 时间、fused_vs_bolt、path_aware_rows、状态码
- 关系：Phase 4 是“统计评估模块集合”。4A 与 4B 是并列子模块，不是同一个脚本的两个输出。

## 推荐执行路径（按目标）

- 目标 A：先打通功能
	路径：Phase 0 -> Phase 1
- 目标 B：评估多基准泛化
	路径：Phase 0 -> Phase 2 -> Phase 4B（suite summary 分析）
- 目标 C：评估多轮渐进式方案
	路径：Phase 0 -> Phase 1（建立基线）-> Phase 3 -> Phase 4

> 注：如果执行目标 C，需要的通常是 Phase 4A（单基准回归）；
> 若要评估“多 benchmark 泛化”，应走 Phase 4B（suite summary）。

## 数据契约（当前）

- `scripts/tools/epp2bolt.py` 输出预聚合与 fdata
- `scripts/tools/fuse_bolt_epp.py` 输出 fused fdata + path-aware sidecar
- path-aware sidecar 最小字段：edge key（src/dst + offset）、fused/path weight、confidence

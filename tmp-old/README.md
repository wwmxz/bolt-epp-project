# bolt-epp-test

BOLT + EPP 融合验证项目（以 llvm-test-suite 基准为主），用于验证：
- 单轮 EPP + BOLT 融合收益
- PathAware sidecar 接入 ext-tsp 的收益
- 多轮采集/合并策略的可行性

## 1. 项目分阶段（Phase）

- Phase 0: 基准准备
- Phase 1: 单基准全流程验证（编译 -> EPP -> BOLT -> 融合 -> 对比）
- Phase 2: 多基准套件验证（profile/testset 可配置）
- Phase 3: 多轮采集与合并（当前有快速版与完整版）
- Phase 4: 结果归档与回归分析

详细说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 2. 模块入口

- 环境与目标集： [docs/modules/module_prepare.md](docs/modules/module_prepare.md)
- 单基准验证与融合： [docs/modules/module_verify_and_fusion.md](docs/modules/module_verify_and_fusion.md)
- 套件与测试集： [docs/modules/module_suite_and_testsets.md](docs/modules/module_suite_and_testsets.md)
- 多轮验证： [docs/modules/module_multiround.md](docs/modules/module_multiround.md)
- 结果与回归： [docs/modules/module_results_and_regression.md](docs/modules/module_results_and_regression.md)
- 模块总索引： [docs/modules/README.md](docs/modules/README.md)
- 成果与规划总览： [docs/PROJECT_STATUS_AND_PLAN.md](docs/PROJECT_STATUS_AND_PLAN.md)

脚本按模块分布在 `scripts/` 下：
- `scripts/prepare/` 或 `scripts/`：准备阶段
- `scripts/verify/`：单基准验证
- `scripts/perf/`：性能测试
- `scripts/suite/`：套件执行
- `scripts/multiround/`：多轮验证
- `scripts/tools/`：融合/转换工具

说明：项目根目录保留同名兼容入口脚本（wrapper），历史命令仍可继续使用。

## 3. 快速开始

1. 准备基准
```bash
bash scripts/prepare_multisource_classics.sh
```

2. 运行单基准全流程验证（Dijkstra）
```bash
bash scripts/verify/verify_dijkstra.sh
```

3. 运行融合版性能对比
```bash
bash scripts/perf/perf_verify_dijkstra_fused.sh
```

4. 运行 PathAware 套件
```bash
bash scripts/suite/run_pathaware_suite.sh --profile stable --testset simple
```

5. 运行多轮完整验证（3 轮真实采集）
```bash
bash scripts/multiround/run_option_b_full_validation.sh
```

## 4. 规范与约束

- 不在 `tmp-old/` 取脚本、二进制或结果。
- Dijkstra 输入优先 `input.dat`。
- PathAware 构建优先使用 `llvm-proj-12.0.1/build-pathaware/bin/` 下的 `llvm-bolt/perf2bolt`。
- 所有性能结论应基于 `results/**.csv`，避免仅看单次运行。

## 5. 后续规划

渐进式 Path Profile 与 ExtTsp 结合规划见：
- [docs/ROADMAP_PROGRESSIVE_PATH_PROFILE_EXTTSP.md](docs/ROADMAP_PROGRESSIVE_PATH_PROFILE_EXTTSP.md)

# 开发规范（后续代码统一遵循）

## 1. 文件组织规范

- 新增脚本优先放在：
  - 单基准流程：`scripts/verify/verify_*.sh` / `scripts/perf/perf_*.sh`
  - 多基准编排：`scripts/suite/run_*.sh`
  - 准备类任务：`scripts/`
  - 测试集配置：`testsets/*.list`
- 新增说明文档放在：`docs/` 或 `docs/modules/`
- 不修改 `llvm-test-suite/` 作为业务逻辑入口（仅作为 benchmark 数据源）

## 2. 命名规范

- 脚本命名：`verify_*`, `perf_*`, `run_*`, `prepare_*`
- 结果目录：`results/<task>/<timestamp_or_case>/`
- CSV 必含字段：variant/time/improvement/fail_rate（按场景可增减）

## 3. 运行规范

- 每个脚本应提供可读的 stage 日志（例如 `[1/7]`）
- 每个关键产物生成后必须做存在性检查（missing 即 fail fast）
- 优先使用 timeout 防止挂死

## 4. 结果规范

- 性能结论必须至少包含：
  - 均值（mean）
  - 稳定性（stddev）
  - 失败率（fail rate）
- 不使用单次运行结果下结论

## 5. 兼容性规范

- BOLT 工具选择顺序：`build-pathaware` > `build`
- Dijkstra 输入优先 `input.dat`
- 发现依赖缺失时输出明确错误与修复建议（脚本/路径）

## 6. Phase C 前置约束

- 多轮功能实现前，不替换现有单轮路径；采用并行新增接口
- 对 sidecar 的扩展必须保持向后兼容（至少保留最小字段）

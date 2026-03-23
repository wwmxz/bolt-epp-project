# 模块：套件执行与测试集（Suite + Testsets）

## 作用

对多个 benchmark 统一执行 PathAware 流程，并输出汇总 CSV。

## 主要文件

- `scripts/suite/run_pathaware_suite.sh`
- `testsets/pathaware_simple.list`
- `testsets/pathaware_large.list`
- `testsets/pathaware_custom.list`

## Profile 模式

- `stable`: alpha=0.6, max_boost=16
- `aggressive`: alpha=1.0, max_boost=48
- `custom`: 由环境变量覆盖

## 使用

```bash
# 默认：stable + simple
bash scripts/suite/run_pathaware_suite.sh

# 激进配置 + large 测试集
bash scripts/suite/run_pathaware_suite.sh --profile aggressive --testset large

# 自定义测试集文件
bash scripts/suite/run_pathaware_suite.sh --testset custom --bench-file testsets/pathaware_custom.list
```

## 输出

- `results/pathaware_suite/<timestamp>_<profile>/summary.csv`
- 每 benchmark 子目录日志与中间产物

## 常见问题

- `llvm-bolt not executable`：检查 `build-pathaware/bin` 或 `build/bin`
- 某 benchmark missing-src/missing-bin：先执行 `prepare_multisource_classics.sh`

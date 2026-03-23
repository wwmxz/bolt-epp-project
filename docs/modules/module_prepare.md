# 模块：准备与编译（Prepare）

## 作用

准备 llvm-test-suite 的目标基准，并生成可执行清单，作为后续所有验证的输入。

## 主要文件

- `scripts/prepare_multisource_classics.sh`
- `scripts/multisource_classics_targets.txt`

## 输入

- C/C++ 编译器（默认 clang/clang++）
- CMake/Ninja
- `llvm-test-suite/` 源码

## 输出

- `build-ts-multisource/`（构建产物）
- `results/multisource_classics_manifest.tsv`

## 使用

```bash
bash scripts/prepare_multisource_classics.sh
```

可选环境变量：

```bash
BUILD_JOBS=16 GENERATOR=Ninja C_COMPILER=clang CXX_COMPILER=clang++ \
bash scripts/prepare_multisource_classics.sh
```

## 常见问题

- 提示 `target list not found`：检查 `scripts/multisource_classics_targets.txt`
- 提示 `cmake not found` 或 `ninja not found`：安装工具或切换 `GENERATOR=Unix Makefiles`

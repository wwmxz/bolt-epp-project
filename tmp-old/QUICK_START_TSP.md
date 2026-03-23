# EPP+BOLT 验证方案：TSP（旅行商问题）

## 概述

本方案选择 **MultiSource TSP** 作为代表性测试目标，用于验证 EPP+BOLT 融合对程序优化的实际效果。

### 为什么选择 TSP？

| 特性 | 说明 |
|------|------|
| **复杂分支结构** | 回溯算法（backtracking）产生大量动态分支 |
| **高分支失败率** | 路径预测挑战大，正是 BOLT 和 EPP 优化的典型场景 |
| **科学代表性** | 展示分支预测对性能的影响 |
| **适中执行时间** | 单次运行约 5-15 秒，验证速度快 |

## 快速验证（10-15 分钟）

### 前提条件

首先需要编译 MultiSource TSP 基准：

```bash
bash scripts/prepare_multisource_classics.sh
```

此脚本会在 `build-ts-multisource/` 中编译所有 11 个基准，包括 TSP。

### 流程一：构建与优化（5-8 分钟）

```bash
bash verify_tsp.sh
```

**执行阶段**（7 个步骤）：

1. **编译基准** - 从源码编译基准二进制 (`tsp_base`)
2. **生成 Bitcode** - 为 EPP 生成 LLVM bitcode
3. **EPP 采样** - 收集路径级的动态分支信息
4. **BOLT 优化** - BOLT 官方流程（instrumentation + 重排）
5. **EPP→BOLT 转换** - 将 EPP 路径数据转换为 BOLT 格式
6. **EPP+BOLT 融合** - 基于 EPP 数据的 BOLT 重排
7. **生成报告** - 统计 fdata 覆盖率与二进制尺寸

**输出文件**：

```
results/verify_tsp/
├── tsp_base                  # 基准二进制
├── tsp_bolt_opt              # BOLT 优化版本
├── tsp_epp_bolt_opt          # EPP+BOLT 融合版本
├── tsp.bolt.fdata            # BOLT 采样数据
├── tsp.epp.fdata             # EPP 转换数据
└── *.log                      # 详细构建日志
```

### 流程二：性能对比（<1 分钟）

```bash
bash perf_verify_tsp.sh
```

**验证内容**：

- 对每个二进制执行 **3 次运行**
- 计算平均执行时间
- 输出改进百分比对比

**输出示例**：

```
Performance Results:
─────────────────────────────────────────────
Baseline execution time:        8.2540s
BOLT improvement:               18.35% faster
EPP+BOLT improvement:           21.78% faster
EPP+BOLT vs BOLT delta:         3.43%

Verification Status:
  ? EPP+BOLT OUTPERFORMS BOLT
    EPP path profiling provides superior branch prediction

Report saved: results/verify_tsp/performance_comparison.csv
```

## 两条命令完成验证

```bash
# 第一步：构建与优化（5-8 分钟）
bash verify_tsp.sh

# 第二步：性能对比（<1 分钟）
bash perf_verify_tsp.sh
```

总运行时间：**10-15 分钟**

## 可视化对比

| 指标 | 基准 | BOLT | EPP+BOLT |
|------|------|------|----------|
| 执行时间 | 1.0× | 0.82× | 0.78× |
| 改进幅度 | - | 18% | 22% |
| Binary 大小 | 基准 | ↓ 2-3% | ↓ 2-3% |
| fdata 行数 | - | ~1000 | ~1500-2000 |

## 诊断与故障排查

### 问题：TSP 二进制未找到

**解决**：

```bash
# 先编译 MultiSource
bash scripts/prepare_multisource_classics.sh

# 然后运行验证
bash verify_tsp.sh
```

### 问题：EPP fdata 为空

**检查**：

```bash
# 查看 EPP 采样日志
tail -50 results/verify_tsp/epp2bolt.log
tail -50 results/verify_tsp/epp_instrument.log
```

**可能原因**：
- EPP 执行未产生路径数据
- objdump 工具不兼容

**解决**：尝试指定其他 objdump：

```bash
# 编辑 verify_tsp.sh 中的 epp2bolt.py 调用
# 改为：--objdump /path/to/gnu-objdump
```

### 问题：BOLT reorder 失败

**检查**：

```bash
tail -50 results/verify_tsp/bolt_optimize.log
tail -50 results/verify_tsp/epp_bolt_optimize.log
```

**可能原因**：
- fdata 格式不正确
- 二进制缺少重定位信息（`--emit-relocs`）

## 高级选项

### 使用其他 MultiSource 基准

如需测试其他具有复杂分支的基准，可修改两个脚本中的：

```bash
BENCHMARK="tsp"              # 改为其他基准名
TS_SRC_DIR="...tsp"          # 改为其他路径
```

**推荐备选方案**：

| 基准 | 特点 | 分支复杂度 |
|------|------|-----------|
| `mst` | 最小生成树 | ???? 高 |
| `em3d` | 3D 电磁模拟 | ??? 中高 |
| `bh` | N-body 物理 | ??? 中高 |
| `network-dijkstra` | 路由算法 | ???? 高 |

### 调整性能测试参数

编辑 `perf_verify_tsp.sh`：

```bash
RUNS=3    # 改为 5-10 可获得更稳定的数据
```

## 预期结果

在典型系统上，EPP+BOLT 相对于 BOLT 的改进应该为：

- **TSP**：3-8% 改进（分支密集，EPP 优势明显）
- **最坏情况**：-2% 到 +2%（无显著改进）
- **最好情况**：8-15% 改进（分支预测失败率高时）

## 输出文件位置

```
results/verify_tsp/
├── performance_comparison.csv   # 最终性能对比报告
├── tsp_*                        # 三个优化版本的二进制
├── tsp.*.fdata                  # BOLT 格式的采样数据
└── *.log                        # 构建过程日志
```

## 下一步

- 如需对比 **多个基准**，直接运行 `bash run_multisource.sh`
- 如需运行 **完整 Stanford 基准**，执行 `bash run_stanford.sh`
- 详见项目根目录的其他验证脚本

---

**创建时间**：2026-03-22  
**验证工具链**：LLVM 5.0.1 (EPP) + LLVM 12.0.1 (BOLT)

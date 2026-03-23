# 模块：单基准验证与融合（Verify + Fusion）

## 作用

在单个 benchmark 上执行全流程：
- baseline 重编译
- EPP 采集与解码
- BOLT 采样与优化
- EPP->BOLT 转换
- BOLT+EPP 融合
- 产物性能对比

## 主要文件

- `scripts/verify/verify_dijkstra.sh`
- `scripts/tools/epp2bolt.py`
- `scripts/tools/fuse_bolt_epp.py`
- `scripts/perf/perf_verify_dijkstra.sh`
- `scripts/perf/perf_verify_dijkstra_fused.sh`
- `scripts/perf/perf_verify_tsp.sh`

## 关键数据流

1. baseline binary
2. llvm bitcode (`*.bc`)
3. epp profile (`*.profile`)
4. bolt fdata (`*.bolt.fdata`)
5. epp fdata (`*.epp.fdata`)
6. fused fdata (`*.fused.fdata`)
7. path-aware sidecar (`*.path_aware.tsv`)

## 使用

```bash
bash scripts/verify/verify_dijkstra.sh
bash scripts/perf/perf_verify_dijkstra_fused.sh
```

## 融合策略（当前）

- `scripts/tools/fuse_bolt_epp.py` 默认保留 BOLT 结构，只提升 edge count
- sidecar 输出字段包含：src/dst key、orig_count、epp_count、fused_count、confidence

## 常见问题

- Dijkstra 输入文件应为 `input.dat`
- `perf2bolt` 失败时优先检查预聚合参数与 objdump 输出
- 若 BOLT 产物缺失，先看 `bolt_instrument.log`、`bolt_optimize.log`
